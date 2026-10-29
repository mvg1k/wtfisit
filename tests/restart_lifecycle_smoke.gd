extends SceneTree

# Run through run_restart_lifecycle.ps1: engine errors must fail the run too.
var _menu: Node
var _observer: Observer
var _checks := 0
var _failures := 0
var _render := false

class Observer extends Node:
	signal frame(delta: float)
	func _process(delta: float) -> void:
		frame.emit(delta)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	_observer = Observer.new()
	_observer.process_priority = 200
	_observer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_observer)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _frames(4)
	_menu = current_scene
	_check(_menu.screen == _menu.Screen.MAIN, "Launch enters Main Menu")
	_activate(_menu.Screen.MAIN, "Play")
	await _frames(6)
	for cycle in 4:
		_check_room("Play %d" % (cycle + 1))
		await _moving_fixture()
		await _pause_and_resume()
		_menu.pause_game()
		await _frames(2)
		var retired := _retiring_nodes()
		_activate(_menu.Screen.PAUSE, "Restart")
		_activate(_menu.Screen.PAUSE, "Restart") # Guard repeated activation in the same frame.
		await _frames(6)
		_check_retired(retired, "Restart %d" % (cycle + 1))
		_check_room("Restart %d" % (cycle + 1))
		await _moving_fixture()
		if _render and cycle == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.validation/restart_active.png")
		_menu.pause_game()
		await _frames(2)
		retired = _retiring_nodes()
		_activate(_menu.Screen.PAUSE, "Main Menu")
		await _frames(6)
		_check_retired(retired, "Main Menu %d" % (cycle + 1))
		_check(_menu.room == null and _menu.get_node("Gameplay").get_child_count() == 0
			and not paused and _menu.screen == _menu.Screen.MAIN,
			"Main Menu clears gameplay and pause state")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Main Menu releases cursor")
		_activate(_menu.Screen.MAIN, "Play")
		await _frames(6)
	_check_room("Final Play")
	_menu.pause_game()
	_activate(_menu.Screen.PAUSE, "Main Menu")
	await _frames(6)
	_check(Engine.physics_ticks_per_second == 60
		and not ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"60-Hz physics and disabled global interpolation preserved")
	print("RESTART LIFECYCLE: %d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _activate(page: int, title: String) -> void:
	# Invoke the actual button connection, including its transition guard.
	for control: Node in _menu._pages[page].get_children():
		if control is Button and control.text == title:
			control.pressed.emit()
			return
	_check(false, "Button exists: " + title)

func _check_room(label: String) -> void:
	var player: SandboxPlayer = _menu.player
	var grabber: PhysicsGrabber = player.get_node("Grabber")
	var visuals: PropVisualInterpolation = grabber._visuals
	_check(_menu.get_node("Gameplay").get_child_count() == 1 and not paused
		and _menu.screen == _menu.Screen.PLAYING and player.mouse_captured,
		label + " has one active room and captured mouse")
	_check(root.get_camera_3d() == player.visual_camera and grabber.camera == player.camera,
		label + " retains separate visual and gameplay cameras")
	var crosshair: Label = _menu.room.get_node("DebugOverlay/Crosshair")
	_check((crosshair.position + crosshair.size * 0.5).distance_to(root.get_visible_rect().size * 0.5) < 0.001,
		label + " crosshair stays at screen centre")
	var count := 0
	var registered := true
	for body in get_nodes_in_group("grabbable"):
		if _menu.room.is_ancestor_of(body):
			count += 1
			registered = registered and visuals._props.has(body) and body.has_meta("prop_visual_interpolation")
			if body.has_meta("prop_visual_interpolation"):
				var reference: WeakRef = body.get_meta("prop_visual_interpolation")
				registered = registered and reference.get_ref() == visuals
	_check(count >= 8 and registered and visuals._props.size() == count,
		label + " registers every prop with only the current helper")

func _moving_fixture() -> void:
	# Real room bottle breaks against the north wall through its normal contact path.
	var bottle: RigidBody3D = _menu.room.get_node("MovableProps/GlassBottle")
	var bottle_ref: WeakRef = weakref(bottle)
	bottle.global_position = Vector3(0.1, 1.2, 0.3)
	bottle.rotation = Vector3.ZERO
	bottle.gravity_scale = 0
	bottle.linear_velocity = Vector3(0, 0, -12)
	var elapsed := 0.0
	while bottle_ref.get_ref() != null and elapsed < 1.5:
		elapsed += await _observer.frame
	await _frames(2)
	var fragments := get_nodes_in_group("impact_debris")
	var moving := 0
	var registered := true
	var visuals: PropVisualInterpolation = _menu.player.get_node("Grabber")._visuals
	for fragment: RigidBody3D in fragments:
		if fragment.linear_velocity.length() > 0.1 and fragment.angular_velocity.length() > 0.1:
			moving += 1
		registered = registered and visuals._props.has(fragment)
	_check(bottle_ref.get_ref() == null and fragments.size() == 4 and moving > 0 and registered,
		"Real wall impact replaces bottle with registered, moving and tumbling fragments")
	var box: RigidBody3D = _menu.room.get_node("MovableProps/MovingBoxA")
	box.apply_central_impulse(Vector3(1, 2, 0))
	await _frames(1)
	_check(box.linear_velocity.length() > 0.1 and visuals._props.has(box),
		"Moving room prop remains registered before teardown")

func _pause_and_resume() -> void:
	var body: RigidBody3D = _menu.room.get_node("MovableProps/MovingBoxA")
	var visuals: PropVisualInterpolation = _menu.player.get_node("Grabber")._visuals
	_menu.pause_game()
	var physical := body.global_transform
	var visual := visuals.get_visual_transform(body)
	await _frames(4)
	_check(paused and body.global_transform == physical and visuals.get_visual_transform(body) == visual
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause freezes moving prop and releases cursor")
	_activate(_menu.Screen.PAUSE, "Resume")
	await _frames(2)
	_check(not paused and _menu.player.mouse_captured and body.global_transform != physical,
		"Resume restores motion and mouse capture")

func _retiring_nodes() -> Array[WeakRef]:
	var retired: Array[WeakRef] = [weakref(_menu.room), weakref(_menu.player.get_node("Grabber")._visuals)]
	for body in get_nodes_in_group("grabbable"):
		if _menu.room.is_ancestor_of(body):
			retired.append(weakref(body))
	return retired

func _check_retired(retired: Array[WeakRef], label: String) -> void:
	var freed := true
	for reference in retired:
		freed = freed and reference.get_ref() == null
	_check(freed, label + " frees old room, smoothing helper, props and fragments")

func _frames(count: int) -> void:
	for frame in count:
		await _observer.frame

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
