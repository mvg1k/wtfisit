class_name SandboxPlayer
extends CharacterBody3D

@export var camera: Camera3D
@export var move_speed: float = 4.5
@export var acceleration: float = 22.0
@export var deceleration: float = 28.0
@export var air_acceleration: float = 7.0
@export var jump_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025

var mouse_captured: bool = false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _ready() -> void:
	set_mouse_captured(true)


func set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_mouse_captured(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		set_mouse_captured(false)
		get_viewport().set_input_as_handled()
		return
	if not mouse_captured:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			set_mouse_captured(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0), deg_to_rad(85.0))


func _physics_process(delta: float) -> void:
	var movement := Vector2.ZERO
	if mouse_captured:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(movement.x, 0.0, movement.y)
	var desired := direction * move_speed
	var rate := acceleration if not movement.is_zero_approx() else deceleration
	if not is_on_floor():
		rate = air_acceleration
		velocity.y -= _gravity * delta
	elif mouse_captured and Input.is_action_just_pressed("jump"):
		velocity.y = jump_speed
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	move_and_slide()
