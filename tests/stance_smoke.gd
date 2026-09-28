extends SceneTree

const ROOM: PackedScene = preload("res://scenes/test_room.tscn")
var _room: Node3D
var _player: SandboxPlayer
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_room = ROOM.instantiate()
	root.add_child(_room)
	_player = _room.get_node("Player") as SandboxPlayer
	await _steps(30)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_CTRL
	_check(InputMap.event_is_action(key, "crouch"), "Ctrl maps to crouch")
	key.physical_keycode = KEY_Z
	_check(InputMap.event_is_action(key, "toggle_prone"), "Z maps to prone")
	_check(_player.stance == SandboxPlayer.Stance.STANDING, "Starts standing")
	Input.action_press("crouch")
	await _steps(3)
	_check(_capsule().height > 1.0 and _capsule().height < 1.8, "Collider eases between heights")
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.CROUCHING and is_equal_approx(_capsule().height, 1.0),
		"Crouch changes actual collider")
	_check(is_equal_approx(_player.camera.position.y, 0.82) and is_equal_approx(_player.body_shape.position.y, 0.5),
		"Crouched camera lowers while feet remain fixed")
	Input.action_press("move_right")
	await _steps(25)
	_check(absf(_player.velocity.x - 2.475) < 0.05, "Crouch movement is slower")
	Input.action_release("move_right")
	Input.action_release("crouch")
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.STANDING and is_equal_approx(_capsule().height, 1.8),
		"Releasing Ctrl returns to standing")
	_prone()
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.PRONE and is_equal_approx(_capsule().height, 0.5),
		"Prone uses half-metre collider")
	_check(is_equal_approx(_player.camera.position.y, 0.28), "Prone camera is near the floor")
	Input.action_press("move_right")
	await _steps(20)
	_check(absf(_player.velocity.x - 1.125) < 0.05, "Prone movement is substantially slower")
	Input.action_release("move_right")
	await _steps(20)
	Input.action_press("jump")
	await _steps(2)
	Input.action_release("jump")
	_check(_player.position.y < 0.05, "Prone does not jump")

	var ceiling := _ceiling(0.7)
	await _steps(3)
	_prone()
	await _steps(20)
	_check(_player.stance == SandboxPlayer.Stance.PRONE and is_equal_approx(_capsule().height, 0.5),
		"Prone-to-standing is blocked by low overhead geometry")
	Input.action_press("crouch")
	await _steps(5)
	_check(_player.stance == SandboxPlayer.Stance.PRONE, "Prone-to-crouch also checks clearance")
	ceiling.position.y = 1.3
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.CROUCHING, "Enough space permits crouching")
	Input.action_release("crouch")
	await _steps(20)
	_check(_player.stance == SandboxPlayer.Stance.CROUCHING and _player.camera.position.y < 1.0,
		"Crouch cannot stand through a ceiling")
	ceiling.queue_free()
	await _steps(25)
	_check(_player.stance == SandboxPlayer.Stance.STANDING and is_equal_approx(_player.camera.position.y, 1.6),
		"Standing resumes when overhead space clears")

	var other := load("res://scenes/player.tscn").instantiate() as SandboxPlayer
	_room.add_child(other)
	other.position = Vector3(-4, 0, 3)
	_prone()
	await _steps(20)
	_check(other.body_shape.shape != _player.body_shape.shape, "Players have independent capsule resources")
	other.queue_free()
	_room.queue_free()
	await process_frame
	print("STANCE SMOKE: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _capsule() -> CapsuleShape3D:
	return _player.body_shape.shape as CapsuleShape3D


func _ceiling(bottom: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 0.2, 3)
	collision.shape = shape
	body.add_child(collision)
	_room.add_child(body)
	body.position = _player.position + Vector3(0, bottom + 0.1, 0)
	return body


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
