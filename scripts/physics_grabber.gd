class_name PhysicsGrabber
extends Node3D

@export var camera: Camera3D
@export var player: SandboxPlayer
@export var player_shape: CollisionShape3D
@export var reach: float = 3.2
@export var hold_distance: float = 2.0
@export var min_hold_distance: float = 1.1
@export var max_hold_distance: float = 3.0
@export var distance_step: float = 0.15
@export var rotation_sensitivity: float = 0.006
@export var rotation_response: float = 14.0
@export var angular_response: float = 18.0
@export var max_angular_speed: float = 6.0
@export var max_angular_acceleration: float = 60.0
@export var max_torque: float = 40.0
@export var max_rotation_lag: float = 0.8
@export var spring_strength: float = 45.0
@export var spring_damping: float = 12.0
@export var max_acceleration: float = 50.0
@export var max_force: float = 240.0
@export var break_distance: float = 2.8
@export var throw_impulse: float = 14.0
@export var max_throw_speed_change: float = 12.0

var held_body: RigidBody3D
var current_hold_distance: float = 2.0
var _minimum_distance: float = 1.1
var _held_radius: float = 0.0
var _rotation_target := Quaternion.IDENTITY
var _saved_angular_damp: float = 0.0
var _obstructed_time: float = 0.0
var _interact_requested: bool = false
var _throw_requested: bool = false
var _released_bodies: Array[RigidBody3D] = []
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _unhandled_input(event: InputEvent) -> void:
	if not player.mouse_captured:
		return
	if is_instance_valid(held_body):
		if event is InputEventMouseMotion and Input.is_action_pressed("rotate_held"):
			var yaw := Quaternion(camera.global_basis.y, event.relative.x * rotation_sensitivity)
			var pitch := Quaternion(camera.global_basis.x, event.relative.y * rotation_sensitivity)
			_rotation_target = (yaw * pitch * _rotation_target).normalized()
			# This child handles motion before the player's camera-look handler.
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("hold_farther") or event.is_action_pressed("hold_closer"):
			var direction := 1.0 if event.is_action_pressed("hold_farther") else -1.0
			var factor: float = event.factor if event is InputEventMouseButton else 1.0
			current_hold_distance = clampf(current_hold_distance + direction * distance_step * factor,
				_minimum_distance, max_hold_distance)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact"):
		_interact_requested = true
	elif event.is_action_pressed("throw_object"):
		_throw_requested = true


func _physics_process(delta: float) -> void:
	_restore_player_collisions()
	if not player.mouse_captured:
		release()
		_interact_requested = false
		_throw_requested = false
		return
	if _interact_requested:
		if is_instance_valid(held_body):
			release()
		else:
			try_pick_up()
	elif _throw_requested:
		release(true)
	_interact_requested = false
	_throw_requested = false
	if is_instance_valid(held_body):
		_update_hold(delta)


func try_pick_up() -> void:
	if is_instance_valid(held_body):
		return
	var hit := _ray(camera.global_position - camera.global_basis.z * reach)
	var body := hit.get("collider") as RigidBody3D
	if body == null or body.freeze or not body.is_in_group("grabbable"):
		return
	_held_radius = _body_radius(body)
	var capsule := player_shape.shape as CapsuleShape3D
	_minimum_distance = maxf(min_hold_distance, _held_radius + capsule.radius + 0.1)
	if _minimum_distance > max_hold_distance:
		return
	current_hold_distance = clampf(hold_distance, _minimum_distance, max_hold_distance)
	_rotation_target = body.global_basis.get_rotation_quaternion()
	held_body = body
	_released_bodies.erase(body)
	_saved_angular_damp = body.angular_damp
	body.angular_damp = maxf(body.angular_damp, 3.0)
	body.add_collision_exception_with(player)
	player.add_collision_exception_with(body)
	body.sleeping = false
	_obstructed_time = 0.0


func release(throw_held: bool = false) -> void:
	if not is_instance_valid(held_body):
		held_body = null
		return
	var body := held_body
	held_body = null
	body.angular_damp = _saved_angular_damp
	# Restore collision only after separation, never inside the player's capsule.
	_released_bodies.append(body)
	if throw_held:
		var impulse := minf(throw_impulse, body.mass * max_throw_speed_change)
		body.apply_central_impulse(-camera.global_basis.z * impulse)


func _update_hold(delta: float) -> void:
	var forward := -camera.global_basis.z
	var target_distance := current_hold_distance
	var wall := _ray(camera.global_position + forward * (target_distance + _held_radius), held_body)
	if not wall.is_empty():
		var distance := camera.global_position.distance_to(wall["position"])
		target_distance = minf(target_distance, distance - _held_radius - 0.05)
	var target := camera.global_position + forward * target_distance
	# If there is no safe space, let go instead of retracting through the player.
	if target_distance < _minimum_distance or not _clear_of_player(target):
		release()
		return
	if forward.dot(held_body.global_position - camera.global_position) < 0.15:
		release()
		return
	var offset := target - held_body.global_position
	var blocked := not _ray(held_body.global_position, held_body).is_empty()
	_obstructed_time = _obstructed_time + delta if blocked else 0.0
	if offset.length() > break_distance or _obstructed_time > 0.25:
		release()
		return
	# A damped spring applies forces; the physics solver owns position and contacts.
	var force_acceleration := offset * spring_strength - held_body.linear_velocity * spring_damping
	force_acceleration += Vector3.UP * _gravity * held_body.gravity_scale
	var force := (force_acceleration.limit_length(max_acceleration) * held_body.mass).limit_length(max_force)
	held_body.apply_central_force(force)
	_update_rotation()


func _update_rotation() -> void:
	if held_body.lock_rotation:
		return
	var current := held_body.global_basis.get_rotation_quaternion()
	var error := (_rotation_target * current.inverse()).normalized()
	if error.w < 0.0:
		error = -error
	var angle := error.get_angle()
	# Discard excess lag against obstacles instead of storing a large rotation.
	if angle > max_rotation_lag:
		_rotation_target = current.slerp(_rotation_target, max_rotation_lag / angle).normalized()
		angle = max_rotation_lag
	var desired_velocity := Vector3.ZERO
	if angle > 0.001:
		desired_velocity = error.get_axis() * minf(angle * rotation_response, max_angular_speed)
	var acceleration := ((desired_velocity - held_body.angular_velocity) * angular_response).limit_length(
		max_angular_acceleration)
	var inverse_inertia := held_body.get_inverse_inertia_tensor()
	if absf(inverse_inertia.determinant()) > 0.000001:
		var torque := (inverse_inertia.inverse() * acceleration).limit_length(max_torque)
		held_body.apply_torque(torque)


func _body_radius(body: RigidBody3D) -> float:
	# Cache a conservative rotation-independent bound only when picking up.
	var radius: float = 0.0
	for owner_id: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var local_transform := body.shape_owner_get_transform(owner_id)
		for index in body.shape_owner_get_shape_count(owner_id):
			var shape := body.shape_owner_get_shape(owner_id, index)
			var bounds := shape.get_debug_mesh().get_aabb()
			for corner in 8:
				radius = maxf(radius, (local_transform * bounds.get_endpoint(corner)).length())
	return radius


func _clear_of_player(target: Vector3) -> bool:
	var capsule := player_shape.shape as CapsuleShape3D
	var half_segment := capsule.height * 0.5 - capsule.radius
	var top := player_shape.to_global(Vector3.UP * half_segment)
	var bottom := player_shape.to_global(Vector3.DOWN * half_segment)
	var closest := Geometry3D.get_closest_point_to_segment(target, top, bottom)
	return target.distance_to(closest) >= _held_radius + capsule.radius + 0.08


func _ray(end: Vector3, ignored: RigidBody3D = null) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, end, 1 | 4)
	var excluded: Array[RID] = [player.get_rid()]
	if is_instance_valid(ignored):
		excluded.append(ignored.get_rid())
	query.exclude = excluded
	return get_world_3d().direct_space_state.intersect_ray(query)


func _restore_player_collisions() -> void:
	if _released_bodies.is_empty():
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player_shape.shape
	query.transform = player_shape.global_transform
	query.margin = 0.06
	query.collision_mask = 4
	var overlaps := get_world_3d().direct_space_state.intersect_shape(query, 64)
	for index in range(_released_bodies.size() - 1, -1, -1):
		var body := _released_bodies[index]
		if not is_instance_valid(body):
			_released_bodies.remove_at(index)
			continue
		var overlapping := false
		for hit in overlaps:
			if hit["collider"] == body:
				overlapping = true
				break
		if not overlapping:
			body.remove_collision_exception_with(player)
			player.remove_collision_exception_with(body)
			_released_bodies.remove_at(index)
