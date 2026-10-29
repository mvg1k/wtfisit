class_name PhysicsGrabber
extends Node3D

signal object_picked_up(body: RigidBody3D)

@export var camera: Camera3D
@export var player: SandboxPlayer
@export var player_shape: CollisionShape3D
@export var reach: float = 1.6
@export var hold_distance: float = 1.0
@export var min_hold_distance: float = 0.75
@export var max_hold_distance: float = 3.0
@export var distance_step: float = 0.15
@export var rotation_sensitivity: float = 0.006
@export var rotation_response: float = 14.0
@export var angular_response: float = 18.0
@export var max_angular_speed: float = 6.0
@export var max_angular_acceleration: float = 60.0
@export var max_torque: float = 40.0
@export var max_rotation_lag: float = 0.8
@export var spring_strength: float = 160.0
@export var spring_damping: float = 24.0
@export var max_acceleration: float = 50.0
@export var max_force: float = 240.0
@export var break_distance: float = 2.8
@export var throw_charge_duration: float = 1.0
@export var toss_speed: float = 4.0
@export var full_throw_speed: float = 19.0
@export var player_throw_inheritance: float = 0.5
@export var max_throw_speed: float = 26.0
@export var max_throw_spin: float = 7.0
@export var kick_reach: float = 1.35
@export var kick_impulse: float = 10.0
@export var kick_max_added_speed: float = 10.0
@export var kick_cooldown: float = 0.45
@export var log_release_reasons: bool = false

var held_body: RigidBody3D
var last_release: Dictionary = {}
var last_pickup_attempt: Dictionary = {}
var pickup_attempts: int = 0
var _overlap_recovery: Dictionary = {}
var is_charging_throw: bool = false
var throw_charge: float:
	get:
		return clampf(_charge_seconds / throw_charge_duration, 0.0, 1.0)
var _charge_seconds: float = 0.0
var _throw_rng := RandomNumberGenerator.new()
var current_hold_distance: float = 1.0
var _minimum_distance: float = 0.75
var _held_radius: float = 0.0
var _held_center := Vector3.ZERO
var _held_points: Array[Vector3] = []
var _held_shapes: Array[Dictionary] = []
var _rotation_target := Quaternion.IDENTITY
var _saved_angular_damp: float = 0.0
var _obstructed_time: float = 0.0
var _hold_target := Vector3.ZERO
var _hold_clearance := "none"
var _hold_sight_blocked := false
var _hold_clearance_normal := Vector3.ZERO
var _hold_clearance_distance := 0.0
var _hold_player_limited := false
var _interact_requested: bool = false
var _throw_requested: bool = false
var _kick_requested: bool = false
var _kick_remaining: float = 0.0
var _released_bodies: Array[RigidBody3D] = []
var _thrown_bodies: Array[RigidBody3D] = []
var _motion_sweep := PropMotionSweep.new()
var _rest := PropRest.new()
var _visuals := PropVisualInterpolation.new()
var _kick_foot_shape := SphereShape3D.new()
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _ready() -> void:
	_throw_rng.randomize()
	_kick_foot_shape.radius = 0.06
	_rest.grabber = self
	add_child(_rest)
	_visuals.grabber = self
	add_child(_visuals)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release(false, 0.4, &"focus_lost")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		release(false, 0.4, &"escape")
		return
	if not player.mouse_captured:
		return
	if event.is_action_pressed("drop_object"):
		# Also discard input queued earlier this frame: a late LMB release or E
		# must not throw or immediately pick the dropped prop back up.
		_interact_requested = false
		var was_holding := is_instance_valid(held_body)
		release(false, 0.4, &"rmb_drop")
		# Decide at input time: dropping must never turn into a kick next tick.
		_kick_requested = not was_holding and _kick_remaining <= 0.0
		get_viewport().set_input_as_handled()
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
		if is_instance_valid(held_body) and not is_charging_throw and not _throw_requested:
			_charge_seconds = 0.0
			is_charging_throw = true
	elif event.is_action_released("throw_object") and is_charging_throw:
		is_charging_throw = false
		_throw_requested = true


func _physics_process(delta: float) -> void:
	_kick_remaining = maxf(0.0, _kick_remaining - delta)
	_restore_player_collisions()
	_update_thrown_bodies(delta)
	if not player.mouse_captured:
		release(false, 0.4, &"cursor_released")
		_interact_requested = false
		_throw_requested = false
		return
	if _kick_requested:
		_kick_requested = false
		_kick()
	elif _interact_requested:
		if is_instance_valid(held_body):
			release(false, 0.4, &"interact_drop")
		else:
			try_pick_up()
	elif _throw_requested:
		release(true, _charge_seconds)
	_interact_requested = false
	_throw_requested = false
	if is_instance_valid(held_body):
		if is_charging_throw:
			_charge_seconds = minf(_charge_seconds + delta, throw_charge_duration)
		_update_hold(delta)
	else:
		_reset_throw_charge()


func try_pick_up() -> void:
	if is_instance_valid(held_body):
		return
	player.visual_camera.reset_if_eye_changed()
	player.visual_camera.sync_rotation()
	var info := _pickup_info()
	pickup_attempts += 1
	last_pickup_attempt = _pickup_summary(info)
	last_pickup_attempt["physics_frame"] = Engine.get_physics_frames()
	last_pickup_attempt["outcome"] = "held" if info.eligible else info.reason
	if not info.eligible:
		return
	var body: RigidBody3D = info.body
	_set_hold_bounds(info.bounds)
	_minimum_distance = info.minimum_distance
	_overlap_recovery = info.recovery.duplicate() if info.has("recovery") else {}
	# A close pickup must not be pushed out to the default preferred distance.
	var pickup_distance := camera.global_position.distance_to(body.to_global(_held_center))
	current_hold_distance = clampf(minf(hold_distance, pickup_distance), _minimum_distance, max_hold_distance)
	_hold_target = camera.global_position - camera.global_basis.z * current_hold_distance
	_hold_clearance = "none"
	_hold_sight_blocked = false
	_hold_clearance_normal = Vector3.ZERO
	_hold_clearance_distance = 0.0
	_hold_player_limited = false
	_rotation_target = body.global_basis.get_rotation_quaternion()
	_reset_throw_charge()
	held_body = body
	_thrown_bodies.erase(body)
	_released_bodies.erase(body)
	if body is ImpactDebris:
		body.set_held(true) # Cache flight damping, never temporary rest damping.
	_saved_angular_damp = body.angular_damp
	body.angular_damp = maxf(body.angular_damp, 3.0)
	body.add_collision_exception_with(player)
	player.add_collision_exception_with(body)
	body.sleeping = false
	body.tree_exiting.connect(_held_body_exiting, CONNECT_ONE_SHOT)
	_obstructed_time = 0.0
	object_picked_up.emit(body)


func cancel_pending_input() -> void:
	# Menus cancel queued pickup/kick/throw before freezing the gameplay tree.
	_interact_requested = false
	release(false, 0.4, &"menu_or_transition")


func release(throw_held: bool = false, charge_seconds: float = 0.4, reason: StringName = &"manual_drop") -> void:
	_kick_requested = false
	_reset_throw_charge()
	if not is_instance_valid(held_body):
		held_body = null
		_overlap_recovery = {}
		return
	var body := held_body
	_record_release(&"throw" if throw_held else reason)
	_overlap_recovery = {}
	if body.tree_exiting.is_connected(_held_body_exiting):
		body.tree_exiting.disconnect(_held_body_exiting)
	held_body = null
	body.angular_damp = _saved_angular_damp
	if body is ImpactDebris:
		body.set_held(false)
	body.sleeping = false
	_rest.track_awake(body)
	# Restore collision only after separation, never inside the player's capsule.
	_released_bodies.append(body)
	if throw_held:
		_apply_throw(body, charge_seconds)
		_thrown_bodies.append(body)
		_limit_throw_motion(body, get_physics_process_delta_time())


func _record_release(reason: StringName) -> void:
	var body := held_body
	last_release = get_hold_diagnostics()
	last_release.merge({"reason": reason, "body": String(body.name),
		"physics_frame": Engine.get_physics_frames(), "position": body.global_position,
		"velocity": body.linear_velocity}, true)
	if log_release_reasons:
		print("GRAB RELEASE: ", last_release)
	if last_pickup_attempt.get("body_id", 0) == body.get_instance_id():
		last_pickup_attempt["outcome"] = String(reason)


func _held_body_exiting() -> void:
	# Destruction/removal ends the hold without driving or re-tracking a dying body.
	if is_inside_tree() and is_instance_valid(held_body):
		_record_release(&"body_removed")
	held_body = null
	_overlap_recovery = {}
	_reset_throw_charge()


func _kick() -> void:
	if is_instance_valid(held_body) or _kick_remaining > 0.0 or not player.mouse_captured:
		return
	_kick_remaining = kick_cooldown # Misses also consume the kick.
	var hit := get_kick_target()
	var body := hit.get("collider") as RigidBody3D
	if body == null:
		return
	var direction := -camera.global_basis.z
	direction.y = 0.0
	direction = (direction.normalized() + Vector3.UP * 0.18).normalized()
	var impulse := direction * minf(kick_impulse, body.mass * kick_max_added_speed)
	if body is ImpactDebris:
		body.set_held(false) # Restore flight damping before waking a settled shard.
	body.sleeping = false
	_rest.track_awake(body)
	body.apply_impulse(impulse, hit.position - body.global_position)
	# Reuse fast-body collision protection; damage still requires an actual
	# collision through ImpactBody, including its confirmed-sweep handoff.
	if not _thrown_bodies.has(body):
		_thrown_bodies.append(body)
	_limit_throw_motion(body, get_physics_process_delta_time())


func get_aim_hit(max_distance: float, hit_from_inside: bool = false) -> Dictionary:
	# Sight queries follow the fixed screen-centre line. The gameplay camera still
	# supplies orientation, physical range, hold targets, rotation and throw forces.
	var view := player.visual_camera
	view.reset_if_eye_changed() # Existing teleport reset; never raycast from a stale eye.
	view.sync_rotation()
	var eye := view.global_position
	var physical_eye := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye,
		eye - camera.global_basis.z * (max_distance + eye.distance_to(physical_eye)), 1 | 4)
	query.exclude = [player.get_rid()]
	query.hit_from_inside = hit_from_inside
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Compensate only presentation parallax, never extend the physical reach.
	if not hit.is_empty() and physical_eye.distance_to(hit.position) > max_distance + 0.0001:
		return {}
	if not hit.is_empty() and not eye.is_equal_approx(physical_eye):
		query.from = physical_eye
		query.to = hit.position
		var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.collider != hit.collider:
			return {} # A rendered-eye offset must not allow reaching around a wall.
	return hit


func get_kick_target() -> Dictionary:
	# Shared by the kick and opt-in diagnostics; querying never applies an impulse.
	if is_instance_valid(held_body) or not player.mouse_captured:
		return {}
	# The camera selects a surface; the lower-body sphere is only a broad gate.
	# It cannot establish that a foot can reach that surface from this platform.
	var origin := player.global_position + Vector3.UP * minf(0.6, camera.position.y)
	var ray_length := kick_reach + origin.distance_to(camera.global_position)
	var hit := get_aim_hit(ray_length, true)
	var body := hit.get("collider") as RigidBody3D
	if body == null or body.freeze or origin.distance_to(hit.position) > kick_reach:
		return {}
	var capsule := player_shape.shape as CapsuleShape3D
	var contact_height: float = hit.position.y - player.global_position.y
	# Do not reach below the current support plane or above a stance-scaled leg
	# envelope. In particular, looking down from a bed cannot kick floor props.
	if contact_height < -0.1 or contact_height > capsule.height * 0.65:
		return {}
	var horizontal: Vector3 = hit.position - player.global_position
	horizontal.y = 0.0
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if horizontal.length() < capsule.radius * 0.5 or forward.is_zero_approx() \
			or horizontal.normalized().dot(forward.normalized()) < 0.5:
		return {} # No underfoot, backward or sideways contact outside the aim cone.
	var foot_origin := player.global_position + Vector3.UP * 0.12
	var foot_distance: float = foot_origin.distance_to(hit.position)
	if foot_distance > kick_reach:
		return {}
	# Visibility alone is insufficient if a low obstacle lies between the leg
	# and the visible target. Both rays must reach this same body first.
	var query := PhysicsRayQueryParameters3D.create(origin, hit.position, 1 | 4)
	query.exclude = [player.get_rid()]
	query.hit_from_inside = true
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty() and obstruction.collider != body:
		return {}
	# A thin knee ray can clear a low rail even though the foot would hit it.
	# Sweep a small foot volume from ankle height; lift only the end of tiny
	# floor contacts so the sole clears the supporting floor. Ignore the selected
	# target, which the foot is meant to contact, but never its support or neighbours.
	var foot_end: Vector3 = hit.position
	foot_end.y = maxf(foot_end.y, player.global_position.y + _kick_foot_shape.radius + 0.01)
	var foot_query := PhysicsShapeQueryParameters3D.new()
	foot_query.shape = _kick_foot_shape
	foot_query.transform = Transform3D(Basis.IDENTITY, foot_origin)
	foot_query.motion = foot_end - foot_origin
	foot_query.collision_mask = 1 | 4
	foot_query.exclude = [player.get_rid(), body.get_rid()]
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(foot_query, 1).is_empty() \
			or space.cast_motion(foot_query)[0] < 1.0:
		return {}
	hit["distance"] = foot_distance
	hit["contact_height"] = contact_height
	return hit


func _reset_throw_charge() -> void:
	is_charging_throw = false
	_charge_seconds = 0.0
	_throw_requested = false


func _throw_mass_factor(mass: float) -> float:
	# A gentle, bounded response keeps heavy household props useful.
	return clampf(pow(2.0 / maxf(mass, 0.01), 0.25), 0.65, 1.2)


func _apply_throw(body: RigidBody3D, charge_seconds: float) -> void:
	var charge := clampf(charge_seconds / throw_charge_duration, 0.0, 1.0)
	var mass_factor := _throw_mass_factor(body.mass)
	var speed := lerpf(toss_speed, full_throw_speed, charge) * mass_factor
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var inherited := (player.velocity * player_throw_inheritance).limit_length(3.0)
	body.linear_velocity = (velocity.limit_length(4.0) + inherited - camera.global_basis.z * speed).limit_length(max_throw_speed)
	if not body.lock_rotation:
		var spin: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		var axis := (camera.global_basis.x + body.global_basis.y * 0.2
			+ camera.global_basis.y * _throw_rng.randf_range(-0.2, 0.2)).normalized()
		var size_factor := 1.0 / maxf(1.0, _body_radius(body) * 1.5)
		var added_spin := lerpf(2.5, 6.0, charge) * mass_factor * size_factor * _throw_rng.randf_range(0.9, 1.1)
		body.angular_velocity = (spin + axis * added_spin).limit_length(max_throw_spin)


func _update_thrown_bodies(delta: float) -> void:
	for index in range(_thrown_bodies.size() - 1, -1, -1):
		var body := _thrown_bodies[index]
		# Native CCD and the contact solver handle slow motion/resting contacts.
		if not is_instance_valid(body) or body.sleeping:
			_thrown_bodies.remove_at(index)
			continue
		var velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		if velocity.length_squared() >= 4.0:
			_limit_throw_motion(body, delta)


func _limit_throw_motion(body: RigidBody3D, delta: float) -> void:
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	body.linear_velocity = _motion_sweep.limit_velocity(body, velocity, delta, [player.get_rid()])


func _update_hold(delta: float) -> void:
	_hold_player_limited = false
	if not _overlap_recovery.is_empty() and _update_overlap_recovery(delta):
		return
	if not is_instance_valid(held_body):
		return
	var forward := -camera.global_basis.z
	var center := held_body.to_global(_held_center)
	# A safe target alone is insufficient: the real body can lag into the player
	# while walking/turning, or be underneath their feet. Stop driving it then.
	if _overlaps_player(held_body):
		release(false, 0.4, &"body_overlaps_player")
		return
	var target_distance := current_hold_distance
	var target := camera.global_position + forward * target_distance
	var wall := _ray(camera.global_position + forward * (target_distance + _held_radius), held_body)
	_hold_clearance = String(wall.collider.name) if not wall.is_empty() else "none"
	_hold_clearance_normal = wall.get("normal", Vector3.ZERO)
	_hold_clearance_distance = camera.global_position.distance_to(wall.position) if not wall.is_empty() else 0.0
	if not wall.is_empty():
		var distance := camera.global_position.distance_to(wall["position"])
		# Clearance along the actual hit plane, including rotated compound props.
		# A bounding sphere overestimates a flat object's height above the floor.
		var normal: Vector3 = wall.normal
		var extent := 0.0
		for point in _held_points:
			extent = maxf(extent, -normal.dot(held_body.global_basis * (point - _held_center)))
		if normal.y > 0.5:
			# Lift the target clear of its support instead of pulling a floor prop
			# back into the player's feet when looking steeply downward.
			target += normal * maxf(0.0, extent + 0.05 - normal.dot(target - wall.position))
		else:
			# Preserve the existing conservative clearance against walls/ceilings.
			target_distance = minf(target_distance, distance - _held_radius - 0.05)
			_hold_target = camera.global_position + forward * target_distance
			target = camera.global_position + forward * target_distance
	_hold_target = target
	# If there is no safe space, let go instead of retracting through the player.
	# The wheel's preferred minimum is not a hard limit for collision-shortened
	# holds. Actual shape overlap/path checks below decide whether they are safe.
	if target_distance < 0.15:
		release(false, 0.4, &"no_target_clearance")
		return
	if not _clear_of_player(target) and (wall.is_empty() or _hold_clearance_normal.y > 0.5):
		# A close downward pickup can be visible/reachable while its preferred
		# 1 m target is inside the capsule. Stop the spring target before the
		# player instead of accepting and immediately dropping the body.
		# Do not extend wall-shortened targets or change the requested distance.
		target = _clip_target_before_player(target)
		_hold_target = target
		_hold_player_limited = true
	if not _clear_of_player(target):
		release(false, 0.4, &"target_overlaps_player")
		return
	if forward.dot(center - camera.global_position) < 0.15:
		release(false, 0.4, &"body_behind_camera")
		return
	var offset := target - center
	# Do not pull an off-axis body across the player's capsule while turning.
	if not _path_clear_of_player(offset):
		release(false, 0.4, &"path_crosses_player")
		return
	var blocked := not _ray(center, held_body).is_empty()
	_hold_sight_blocked = blocked
	_obstructed_time = _obstructed_time + delta if blocked else 0.0
	if offset.length() > break_distance or _obstructed_time > 0.25:
		release(false, 0.4, &"tracking_error" if offset.length() > break_distance else &"sight_obstructed_timeout")
		return
	_apply_hold_force(target)


func _apply_hold_force(target: Vector3) -> void:
	# Both ordinary holding and outward recovery use the unchanged physical spring.
	var offset := target - held_body.to_global(_held_center)
	var force_acceleration := offset * spring_strength - held_body.linear_velocity * spring_damping
	force_acceleration += Vector3.UP * _gravity * held_body.gravity_scale
	var force := (force_acceleration.limit_length(max_acceleration) * held_body.mass).limit_length(max_force)
	held_body.apply_central_force(force)
	_update_rotation()


func get_hold_diagnostics() -> Dictionary:
	# Opt-in F3/test snapshot; never feeds distances or contacts back into control.
	if not is_instance_valid(held_body):
		return {}
	var center := held_body.to_global(_held_center)
	var visual_center := _visuals.get_visual_transform(held_body) * _held_center
	var contact := _player_contact(held_body, _held_shapes, held_body.global_transform)
	return {"requested_distance": current_hold_distance,
		"actual_distance": camera.global_position.distance_to(center),
		"pivot_distance": camera.global_position.distance_to(held_body.global_position),
		"visual_distance": player.visual_camera.global_position.distance_to(visual_center),
		"local_center": _held_center, "target_position": _hold_target,
		"target_distance": camera.global_position.distance_to(_hold_target),
		"target_error": center.distance_to(_hold_target),
		"clearance_collider": _hold_clearance, "sight_blocked": _hold_sight_blocked,
		"clearance_normal": _hold_clearance_normal, "clearance_distance": _hold_clearance_distance,
		"obstructed_seconds": _obstructed_time,
		"player_limited_target": _hold_player_limited,
		"recovery_active": not _overlap_recovery.is_empty(),
		"recovery_direction": _overlap_recovery.get("direction", "none"),
		"player_overlap": contact.depth > 0.0001, "current_depth": contact.depth,
		"padded_overlap": _overlaps_player(held_body), "target_overlap": not _clear_of_player(_hold_target),
		"solver_contacts": held_body._touching.size() if held_body is ImpactBody else -1}


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


func _cache_hold_bounds(body: RigidBody3D) -> void:
	_set_hold_bounds(_get_hold_bounds(body))


func _set_hold_bounds(bounds: Dictionary) -> void:
	_held_center = bounds.center
	_held_radius = bounds.radius
	_held_points = bounds.points
	_held_shapes = bounds.shapes


func _get_hold_bounds(body: RigidBody3D) -> Dictionary:
	# Pure query: F3 must not replace the active held body's cached geometry.
	var points: Array[Vector3] = []
	var shapes: Array[Dictionary] = []
	for owner_id: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		for index in body.shape_owner_get_shape_count(owner_id):
			var shape := body.shape_owner_get_shape(owner_id, index)
			shapes.append({"shape": shape, "transform": body.shape_owner_get_transform(owner_id)})
			var bounds := shape.get_debug_mesh().get_aabb()
			for corner in 8:
				points.append(body.shape_owner_get_transform(owner_id) * bounds.get_endpoint(corner))
	if points.is_empty():
		return {}
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return {"center": bounds.get_center(), "radius": bounds.size.length() * 0.5,
		"points": points, "shapes": shapes}


func _clip_target_before_player(target: Vector3) -> Vector3:
	var center := held_body.to_global(_held_center)
	var offset := target - center
	if offset.length_squared() < 0.000001 or not _clear_of_player(center):
		return target
	var safe := 0.0
	var unsafe := 1.0
	# Use the exact final overlap query: sweep and overlap margins differ at
	# rounded capsule contacts. Only search when the current pose is clear.
	for iteration in 6:
		var fraction := (safe + unsafe) * 0.5
		if _clear_of_player(center + offset * fraction):
			safe = fraction
		else:
			unsafe = fraction
	return center + offset * maxf(0.0, safe - 0.01 / offset.length())


func _pickup_info() -> Dictionary:
	# Inspect the first surface beyond reach too, solely to explain rejection.
	# Eligibility still uses the original physical-eye 1.6 m surface limit.
	var eye := player.visual_camera.global_position
	var physical_eye := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye,
		eye - camera.global_basis.z * (reach * 2.0 + eye.distance_to(physical_eye)), 1 | 4)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var info := {"hit": hit, "body": null, "eligible": false, "reason": "no_surface",
		"surface_distance": -1.0, "occluder": "none", "player_overlap": false,
		"padded_overlap": false, "current_depth": 0.0, "target_overlap": false,
		"recovery_rejection": "none"}
	if hit.is_empty():
		return info
	info.body = hit.collider as RigidBody3D
	info.surface_distance = physical_eye.distance_to(hit.position)
	if info.surface_distance > reach + 0.0001:
		info.reason = "out_of_reach"
		return info
	if not eye.is_equal_approx(physical_eye):
		query.from = physical_eye
		query.to = hit.position
		var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.collider != hit.collider:
			info.reason = "physical_eye_occluded"
			info.occluder = String(obstruction.collider.name)
			return info
	var body: RigidBody3D = info.body
	if body == null or not body.is_in_group("grabbable"):
		info.reason = "surface_not_grabbable"
		info.occluder = String(hit.collider.name)
		return info
	if body.freeze:
		info.reason = "body_frozen"
		return info
	info.bounds = _get_hold_bounds(body)
	if info.bounds.is_empty():
		info.reason = "no_enabled_shape"
		return info
	info.minimum_distance = maxf(min_hold_distance,
		info.bounds.radius + (player_shape.shape as CapsuleShape3D).radius + 0.1)
	if info.minimum_distance > max_hold_distance:
		info.reason = "body_too_large"
		return info
	var exact := _player_contact(body, info.bounds.shapes, body.global_transform)
	info.current_depth = exact.depth
	info.player_overlap = exact.depth > 0.0001
	info.padded_overlap = _overlaps_player(body)
	var preferred := clampf(minf(hold_distance, physical_eye.distance_to(body.to_global(info.bounds.center))),
		info.minimum_distance, max_hold_distance)
	var proposed := body.global_transform
	proposed.origin += physical_eye - camera.global_basis.z * preferred - body.to_global(info.bounds.center)
	info.target_overlap = _player_contact(body, info.bounds.shapes, proposed, 0.08).count > 0
	if info.padded_overlap:
		info.recovery = _plan_overlap_recovery(body, info.bounds, exact)
		if not info.recovery.get("valid", false):
			info.reason = "body_overlaps_player"
			info.recovery_rejection = info.recovery.reason
			return info
	info.eligible = true
	info.reason = "ready_recoverable_overlap" if info.padded_overlap else "ready"
	return info


func _pickup_summary(info: Dictionary) -> Dictionary:
	var collider: CollisionObject3D = info.hit.get("collider")
	var body: RigidBody3D = info.body
	return {"aimed_collider": String(collider.name) if is_instance_valid(collider) else "none",
		"pickup_body": String(body.name) if is_instance_valid(body) else "none",
		"body_id": body.get_instance_id() if is_instance_valid(body) else 0,
		"surface_distance": info.surface_distance, "eligible": info.eligible,
		"reason": info.reason, "occluder": info.occluder, "player_overlap": info.player_overlap,
		"current_depth": info.current_depth, "padded_overlap": info.padded_overlap,
		"target_overlap": info.target_overlap, "recovery_rejection": info.recovery_rejection,
		"recovery_direction": info.get("recovery", {}).get("direction", "none"),
		"recovery_candidates": info.get("recovery", {}).get("candidates", 0)}


func get_pickup_diagnostics() -> Dictionary:
	# No input, transform, hold-cache or attempt-state mutations from F3.
	var result := _pickup_summary(_pickup_info())
	if get_tree().paused or not player.mouse_captured or is_instance_valid(held_body):
		result.eligible = false
		result.reason = "paused" if get_tree().paused else "cursor_released" if not player.mouse_captured else "already_holding"
	result["input_queued"] = _interact_requested
	return result


func _player_contact(body: RigidBody3D, shapes: Array, pose: Transform3D, margin: float = 0.0) -> Dictionary:
	var result := {"depth": 0.0, "count": 0, "per_shape": []}
	for entry in shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = pose * entry.transform
		query.margin = margin
		query.collision_mask = 2 # The actual Player capsule, without resizing it.
		var contacts := body.get_world_3d().direct_space_state.collide_shape(query, 16)
		var depth := 0.0
		for index in range(0, contacts.size(), 2):
			depth = maxf(depth, contacts[index].distance_to(contacts[index + 1]))
		result.per_shape.append(depth)
		result.depth = maxf(result.depth, depth)
		result.count += contacts.size() / 2
	return result


func _world_contact(body: RigidBody3D, shapes: Array, pose: Transform3D) -> Dictionary:
	var result := {"depths": {}, "normals": [], "overflow": false}
	for index in shapes.size():
		var entry: Dictionary = shapes[index]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = pose * entry.transform
		query.margin = 0.0
		query.collision_mask = 1 | 4
		query.exclude = [body.get_rid(), player.get_rid()]
		var space := body.get_world_3d().direct_space_state
		var hits := space.intersect_shape(query, 32)
		if hits.size() == 32:
			result.overflow = true
		for hit in hits:
			var excluded: Array[RID] = [body.get_rid(), player.get_rid()]
			for other in hits:
				if other.rid != hit.rid:
					excluded.append(other.rid)
			query.exclude = excluded
			var contacts := space.collide_shape(query, 16)
			var key := "%d:%d" % [index, hit.rid.get_id()]
			var depth := 0.0
			for pair in range(0, contacts.size(), 2):
				var separation: Vector3 = contacts[pair + 1] - contacts[pair]
				depth = maxf(depth, separation.length())
				if separation.length() > 0.0001:
					result.normals.append(separation.normalized())
			result.depths[key] = depth
	return result


func _recovery_path_safe(body: RigidBody3D, bounds: Dictionary, offset: Vector3,
		initial: Dictionary, world: Dictionary) -> bool:
	if world.overflow:
		return false
	# cast_motion ignores already-intersecting shapes. Check their contact
	# normals and depths too; a support is allowed only without deeper entry.
	for normal: Vector3 in world.normals:
		if offset.dot(normal) < -0.0001:
			return false
	for entry in bounds.shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = body.global_transform * entry.transform
		query.motion = offset
		query.margin = 0.0
		query.collision_mask = 1 | 4
		query.exclude = [body.get_rid(), player.get_rid()]
		if body.get_world_3d().direct_space_state.cast_motion(query)[0] < 0.9999:
			return false
	var previous: Array = initial.per_shape
	for step in 8:
		var pose := body.global_transform
		pose.origin += offset * ((step + 1) / 8.0)
		var contact := _player_contact(body, bounds.shapes, pose)
		for index in previous.size():
			if contact.per_shape[index] > previous[index] + 0.0005:
				return false
		previous = contact.per_shape
		var sample := _world_contact(body, bounds.shapes, pose)
		if sample.overflow:
			return false
		for key in sample.depths:
			if sample.depths[key] > world.depths.get(key, 0.0) + 0.002:
				return false
	return true


func _plan_overlap_recovery(body: RigidBody3D, bounds: Dictionary, contact: Dictionary) -> Dictionary:
	var center := body.to_global(bounds.center)
	var direction := center - player.global_position
	direction.y = 0
	if direction.length() < (player_shape.shape as CapsuleShape3D).radius * 0.5:
		return {"valid": false, "reason": "under_player"}
	direction = direction.normalized()
	if body.linear_velocity.dot(direction) < -0.05:
		return {"valid": false, "reason": "inward_velocity"}
	var world := _world_contact(body, bounds.shapes, body.global_transform)
	if world.overflow:
		return {"valid": false, "reason": "contact_budget_exceeded"}
	var limit: float = bounds.radius + (player_shape.shape as CapsuleShape3D).radius + 0.1
	var side := direction.cross(Vector3.UP)
	var directions := [direction, (direction + side).normalized(), (direction - side).normalized(),
		side, -side, (direction + Vector3.UP).normalized(), Vector3.UP]
	var names := ["outward", "outward_right", "outward_left", "right", "left", "outward_up", "up"]
	var blocked := false
	# Plan only on a pickup attempt or the 5 Hz F3 preview. During recovery keep
	# this one target; the physics loop validates its path without searching again.
	for candidate in directions.size():
		for step in range(1, ceili(limit / 0.025) + 1):
			var offset: Vector3 = directions[candidate] * step * 0.025
			var pose := body.global_transform
			pose.origin += offset
			if _player_contact(body, bounds.shapes, pose, 0.08).count > 0:
				continue
			if camera.global_position.distance_to(center + offset) > max_hold_distance \
					or not _recovery_path_safe(body, bounds, offset, contact, world):
				blocked = true
				break
			return {"valid": true, "target": center + offset, "previous": contact, "initial": contact,
				"world": world, "elapsed": 0.0, "bounds": bounds,
				"direction": names[candidate], "candidates": candidate + 1}
	return {"valid": false, "reason": "no_safe_recovery_path" if blocked else "no_clear_recovery_pose",
		"candidates": directions.size()}


func _update_overlap_recovery(delta: float) -> bool:
	var recovery := _overlap_recovery
	var contact := _player_contact(held_body, _held_shapes, held_body.global_transform)
	for index in contact.per_shape.size():
		if contact.per_shape[index] > minf(recovery.previous.per_shape[index], recovery.initial.per_shape[index]) + 0.002:
			release(false, 0.4, &"overlap_recovery_worsened")
			return true
	var world := _world_contact(held_body, _held_shapes, held_body.global_transform)
	for key in world.depths:
		if world.depths[key] > recovery.world.depths.get(key, 0.0) + 0.002:
			release(false, 0.4, &"overlap_recovery_world_blocked")
			return true
	if _clear_of_player(held_body.to_global(_held_center)):
		_overlap_recovery = {}
		return false # Resume the existing target-clamping/holding code this tick.
	var offset: Vector3 = recovery.target - held_body.to_global(_held_center)
	if not _clear_of_player(recovery.target) or not _recovery_path_safe(held_body, recovery.bounds, offset, contact, world):
		release(false, 0.4, &"overlap_recovery_escape_blocked")
		return true
	recovery.elapsed += delta
	if recovery.elapsed > 1.0:
		release(false, 0.4, &"overlap_recovery_timeout")
		return true
	recovery.previous = contact
	_hold_target = recovery.target
	_hold_player_limited = true
	_apply_hold_force(recovery.target)
	return true


func _overlaps_player(body: RigidBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player_shape.shape
	query.transform = player_shape.global_transform
	query.margin = 0.06
	query.collision_mask = 4
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
		if hit.collider == body:
			return true
	return false


func _clear_of_player(target: Vector3) -> bool:
	var offset := target - held_body.to_global(_held_center)
	for entry in _held_shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = held_body.global_transform * entry.transform
		query.transform.origin += offset
		query.margin = 0.08
		query.collision_mask = 2
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func _path_clear_of_player(offset: Vector3) -> bool:
	for entry in _held_shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = entry.shape
		query.transform = held_body.global_transform * entry.transform
		query.motion = offset
		query.margin = 0.04
		query.collision_mask = 2
		if get_world_3d().direct_space_state.cast_motion(query)[0] < 1.0:
			return false
	return true


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
