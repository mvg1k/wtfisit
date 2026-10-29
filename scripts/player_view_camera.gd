class_name PlayerViewCamera
extends Camera3D

# Presentation only. All gameplay continues to use the original Camera3D.
@export var gameplay_camera: Camera3D
@export var player: CharacterBody3D

var aim_screen_offset := Vector2.ZERO
var _previous_eye := Vector3.ZERO
var _current_eye := Vector3.ZERO
var _initialized: bool = false
var _clearance := SphereShape3D.new()
var _resume_eye := Vector3.ZERO
var _resume_elapsed: float = INF


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Update before the HUD, so its reticle uses this frame's view transform.
	process_priority = -10
	sync_projection()
	reset_interpolation()
	make_current()


func sync_projection() -> void:
	fov = gameplay_camera.fov
	near = gameplay_camera.near
	far = gameplay_camera.far
	keep_aspect = gameplay_camera.keep_aspect
	projection = gameplay_camera.projection
	size = gameplay_camera.size
	frustum_offset = gameplay_camera.frustum_offset
	h_offset = gameplay_camera.h_offset
	v_offset = gameplay_camera.v_offset
	cull_mask = gameplay_camera.cull_mask


func sync_rotation() -> void:
	global_basis = gameplay_camera.global_basis


func reset_interpolation(preserve_view: bool = false) -> void:
	_previous_eye = gameplay_camera.global_position
	_current_eye = _previous_eye
	_initialized = true
	_resume_elapsed = INF
	if not preserve_view:
		global_transform = gameplay_camera.global_transform
		aim_screen_offset = Vector2.ZERO


func reset_if_eye_changed() -> void:
	# Catch even small external position writes before physics moves the player.
	if not _initialized or not gameplay_camera.global_position.is_equal_approx(_current_eye):
		reset_interpolation()


func capture_physics_eye() -> void:
	_previous_eye = _current_eye
	_current_eye = gameplay_camera.global_position


func _notification(what: int) -> void:
	if not _initialized:
		return
	if what == NOTIFICATION_PAUSED:
		reset_interpolation(true) # Freeze the displayed pose without snapping to the tick.
	elif what == NOTIFICATION_UNPAUSED:
		if not gameplay_camera.global_position.is_equal_approx(_current_eye):
			reset_interpolation() # A teleport during pause must not leave a camera trail.
		else:
			_resume_eye = global_position
			reset_interpolation(true)
			_resume_elapsed = 0.0


func _process(delta: float) -> void:
	reset_if_eye_changed()
	sync_rotation()
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var eye := _previous_eye.lerp(_current_eye, fraction)
	# Fresh history after resume; blend from the frozen view for at most one tick.
	var tick_seconds := 1.0 / Engine.physics_ticks_per_second
	if _resume_elapsed < tick_seconds:
		_resume_elapsed = minf(_resume_elapsed + delta, tick_seconds)
		eye = _resume_eye.lerp(eye, _resume_elapsed / tick_seconds)
	global_position = _clear_eye_path(eye)
	_update_aim_offset()


func _clear_eye_path(eye: Vector3) -> Vector3:
	if eye.is_equal_approx(_current_eye):
		return eye
	# Enclose the near plane, not just its centre, in a conservative swept sphere.
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var half_height := near * tan(deg_to_rad(fov * 0.5))
	var half_width := half_height * aspect
	if keep_aspect == Camera3D.KEEP_WIDTH:
		half_width = half_height
		half_height = half_width / maxf(aspect, 0.001)
	_clearance.radius = Vector3(half_width, half_height, near).length()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.transform = Transform3D(Basis.IDENTITY, _current_eye)
	query.motion = eye - _current_eye
	query.margin = 0.001
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	var space := get_world_3d().direct_space_state
	# cast_motion ignores colliders already overlapping the starting sphere.
	# In that case retain the authoritative eye instead of extending its clipping.
	if not space.intersect_shape(query, 1).is_empty():
		return _current_eye
	var fractions := space.cast_motion(query)
	return _current_eye.lerp(eye, fractions[0])


func _update_aim_offset() -> void:
	aim_screen_offset = Vector2.ZERO
	if global_position.is_equal_approx(gameplay_camera.global_position):
		return
	# Keep the existing ray/target/range. Only its on-screen indicator is projected
	# from the visual eye, preventing a centred reticle selecting a nearby neighbour.
	var grabber := player.get_node("Grabber")
	var eye := gameplay_camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye,
		eye - gameplay_camera.global_basis.z * grabber.reach, player.collision_mask)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and not is_position_behind(hit.position):
		aim_screen_offset = unproject_position(hit.position) - get_viewport().get_visible_rect().size * 0.5
