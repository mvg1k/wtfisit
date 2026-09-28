class_name PhysicsGrabber
extends Node3D

@export var camera: Camera3D
@export var player: SandboxPlayer
@export var player_shape: CollisionShape3D
@export var reach: float = 3.2
@export var hold_distance: float = 2.0
@export var spring_strength: float = 45.0
@export var spring_damping: float = 12.0
@export var max_acceleration: float = 50.0
@export var max_force: float = 240.0
@export var break_distance: float = 2.8
@export var throw_impulse: float = 14.0
@export var max_throw_speed_change: float = 12.0

var held_body: RigidBody3D
var _saved_angular_damp: float = 0.0
var _obstructed_time: float = 0.0
var _interact_requested: bool = false
var _throw_requested: bool = false
var _released_bodies: Array[RigidBody3D] = []
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _unhandled_input(event: InputEvent) -> void:
	if not player.mouse_captured:
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
	var target := camera.global_position + forward * hold_distance
	var wall := _ray(target, held_body)
	if not wall.is_empty():
		var distance := camera.global_position.distance_to(wall["position"])
		target = camera.global_position + forward * maxf(0.35, distance - 0.45)
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
