class_name SandboxPlayer
extends CharacterBody3D

enum Stance { STANDING, CROUCHING, PRONE }
const HEIGHTS: Array[float] = [1.8, 1.0, 0.5]
const EYE_HEIGHTS: Array[float] = [1.6, 0.82, 0.28]
const RADII: Array[float] = [0.3, 0.3, 0.24]

@export var camera: Camera3D
@export var body_shape: CollisionShape3D
@export var stance_transition_speed: float = 6.0
@export var move_speed: float = 5.4
@export var crouch_speed: float = 2.475
@export var prone_speed: float = 1.125
@export var acceleration: float = 22.0
@export var deceleration: float = 28.0
@export var air_acceleration: float = 7.0
@export var jump_speed: float = 5.0
@export var mouse_sensitivity: float = 0.0025
@export var push_force: float = 100.0
@export var push_speed: float = 2.8

var mouse_captured: bool = false
var stance: Stance = Stance.STANDING
var _prone_requested: bool = false
var _capsule: CapsuleShape3D
var _clearance_shape := CapsuleShape3D.new()
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _blocked_seconds: float = 0.0
var _escape_remaining: float = 0.0
var _escape_cooldown: float = 0.0


func _ready() -> void:
	body_shape.shape = body_shape.shape.duplicate()
	_capsule = body_shape.shape as CapsuleShape3D
	# Do not inherit contact jitter as take-off velocity from movable props.
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
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
	if event.is_action_pressed("toggle_prone"):
		_prone_requested = not _prone_requested
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-85.0), deg_to_rad(85.0))


func _physics_process(delta: float) -> void:
	_update_stance(delta)
	var movement := Vector2.ZERO
	if mouse_captured:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(movement.x, 0.0, movement.y)
	var speed := move_speed
	if stance == Stance.CROUCHING:
		speed = crouch_speed
	elif stance == Stance.PRONE:
		speed = prone_speed
	var desired := direction * speed
	var rate := acceleration if not movement.is_zero_approx() else deceleration
	if not is_on_floor():
		rate = air_acceleration
		velocity.y -= _gravity * delta
	elif mouse_captured and stance != Stance.PRONE and Input.is_action_just_pressed("jump"):
		velocity.y = jump_speed
	velocity.x = move_toward(velocity.x, desired.x, rate * delta)
	velocity.z = move_toward(velocity.z, desired.z, rate * delta)
	var before := global_position
	move_and_slide()
	_push_contacts(desired, global_position - before, delta)


func _push_contacts(desired: Vector3, travel: Vector3, delta: float) -> void:
	# move_and_slide removes blocked velocity; retain movement intent separately.
	# Collect each actual side contact once, irrespective of manifold/slide count.
	var contacts: Dictionary = {}
	for slide in get_slide_collision_count():
		var collision := get_slide_collision(slide)
		for index in collision.get_collision_count():
			var body := collision.get_collider(index) as RigidBody3D
			var normal := collision.get_normal(index)
			if body == null or body.freeze or absf(normal.y) > 0.5:
				continue # Never push a support underfoot or convert walking to lift.
			var outward := -Vector3(normal.x, 0, normal.z).normalized()
			if not contacts.has(body) or desired.dot(outward) > desired.dot(contacts[body]):
				contacts[body] = outward
	var walking := desired.length_squared() > 0.01
	var progress := Vector3(travel.x, 0, travel.z).length() / delta
	_blocked_seconds = _blocked_seconds + delta if walking and progress < 0.12 and contacts.size() >= 2 else 0.0
	var opposed := false
	var normals: Array = contacts.values()
	for first in normals.size():
		for second in range(first + 1, normals.size()):
			opposed = opposed or normals[first].dot(normals[second]) < -0.5
	# A shared force budget prevents multiple simultaneous props multiplying
	# the player's strength. Central horizontal impulses add no artificial torque.
	var budget := push_force * delta / maxf(1, contacts.size())
	for body: RigidBody3D in contacts:
		var direction: Vector3 = contacts[body]
		var requested := maxf(0, desired.dot(direction))
		if not walking or requested < 0.02:
			continue
		var target_speed := minf(requested, push_speed / (1.0 + body.mass / 6.0))
		var body_velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var speed_gap := maxf(0, target_speed - body_velocity.dot(direction))
		var impulse := minf(budget, body.mass * minf(speed_gap * 16.0, 30.0) * delta)
		if impulse > 0:
			body.apply_central_impulse(direction * impulse)
	# If two opposed contacts still prevent progress, briefly back out through
	# collision-tested motion. No position writes, upward motion or exceptions.
	_escape_cooldown = maxf(0, _escape_cooldown - delta)
	if walking and opposed and _blocked_seconds > 0.5 and _escape_cooldown <= 0 and is_on_floor():
		_escape_remaining = 0.12
		_escape_cooldown = 1.5
	if _escape_remaining > 0 and walking and opposed:
		var distance := minf(_escape_remaining, 0.35 * delta)
		move_and_collide(-desired.normalized() * distance)
		_escape_remaining -= distance
	else:
		_escape_remaining = 0.0


func _update_stance(delta: float) -> void:
	var requested := stance
	if mouse_captured:
		requested = Stance.PRONE if _prone_requested else (
			Stance.CROUCHING if Input.is_action_pressed("crouch") else Stance.STANDING)
	if requested != stance:
		if HEIGHTS[requested] <= _capsule.height and RADII[requested] <= _capsule.radius:
			stance = requested
		elif can_fit_stance(requested):
			stance = requested
	# Keep the feet fixed while the capsule and eye height ease into the stance.
	var height := move_toward(_capsule.height, HEIGHTS[stance], stance_transition_speed * delta)
	var radius := move_toward(_capsule.radius, RADII[stance], stance_transition_speed * delta)
	if height > _capsule.height and not can_fit_stance(stance):
		height = _capsule.height
		radius = _capsule.radius
	if not is_equal_approx(height, _capsule.height) or not is_equal_approx(radius, _capsule.radius):
		_capsule.radius = minf(radius, height * 0.5)
		_capsule.height = height
		body_shape.position.y = height * 0.5
	camera.position.y = minf(height - 0.1,
		move_toward(camera.position.y, EYE_HEIGHTS[stance], stance_transition_speed * delta))


func can_fit_stance(requested: Stance) -> bool:
	_clearance_shape.radius = RADII[requested]
	_clearance_shape.height = HEIGHTS[requested]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance_shape
	query.transform = global_transform
	query.transform.origin += Vector3.UP * (HEIGHTS[requested] * 0.5 + 0.01)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
