class_name PropVisualInterpolation
extends Node

# Local presentation only: the project-wide interpolation switch stays off.
# Node/physics transforms, authored mesh offsets and gameplay queries are untouched.
var grabber: PhysicsGrabber
var _props: Dictionary = {}


func _ready() -> void:
	process_physics_priority = 100
	process_priority = 50
	get_tree().node_added.connect(_node_added)
	RenderingServer.frame_pre_draw.connect(_render_meshes)
	_register_existing.call_deferred()


func _register_existing() -> void:
	for body in get_tree().get_nodes_in_group("grabbable"):
		_register(body)


func _node_added(node: Node) -> void:
	if node is RigidBody3D:
		# Placement and fragment construction finish before recording the first pose.
		_register.call_deferred(node)


func _register(node: Variant) -> void:
	# The outgoing room can receive deferred registrations before queue_free runs.
	if not is_inside_tree() or not is_instance_valid(node) \
			or not is_instance_valid(grabber) or not grabber.is_inside_tree():
		return
	var body := node as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree() or _props.has(body) \
			or not body.is_in_group("grabbable") or body.get_world_3d() != grabber.get_world_3d():
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(body, meshes)
	_props[body] = {"previous": body.global_transform, "current": body.global_transform,
		"visual": body.global_transform, "meshes": meshes, "resume": body.global_transform,
		"elapsed": INF, "submitted": null}
	body.set_meta("prop_visual_interpolation", weakref(self))
	body.tree_exiting.connect(_unregister.bind(body))


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			continue
		if child is MeshInstance3D:
			meshes.append(child)
		_collect_meshes(child, meshes)


func _unregister(body: RigidBody3D) -> void:
	_props.erase(body)


func reset(body: RigidBody3D) -> void:
	if not _props.has(body):
		return
	var sample: Dictionary = _props[body]
	sample.previous = body.global_transform
	sample.current = body.global_transform
	sample.visual = body.global_transform
	sample.elapsed = INF


func get_visual_transform(body: RigidBody3D) -> Transform3D:
	return _props[body].visual if _props.has(body) else body.global_transform


func seed_replacement(body: RigidBody3D, source: RigidBody3D) -> void:
	if not _props.has(source):
		return
	_register(body)
	var sample: Dictionary = _props[body]
	# Continue at the last displayed source pose, retaining the safe physical
	# fragment offsets. Only presentation catches up over one physics tick.
	var correction := get_visual_transform(source) * source.global_transform.affine_inverse()
	sample.resume = correction * body.global_transform
	sample.visual = sample.resume
	sample.elapsed = 0.0


func _physics_process(_delta: float) -> void:
	for body: RigidBody3D in _props:
		var sample: Dictionary = _props[body]
		sample.previous = sample.current
		sample.current = body.global_transform


func _process(delta: float) -> void:
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var tick_seconds := 1.0 / Engine.physics_ticks_per_second
	for body: RigidBody3D in _props:
		var sample: Dictionary = _props[body]
		# External placement/teleport outside physics must never interpolate a trail.
		if not body.global_transform.is_equal_approx(sample.current):
			reset(body)
		var pose: Transform3D = sample.current if sample.previous.is_equal_approx(sample.current) \
			else sample.previous.interpolate_with(sample.current, fraction)
		if sample.elapsed < tick_seconds:
			sample.elapsed = minf(sample.elapsed + delta, tick_seconds)
			pose = sample.resume.interpolate_with(pose, sample.elapsed / tick_seconds)
		sample.visual = _clear_pose(body, pose, sample.current, sample.previous)


func _render_meshes() -> void:
	for body: RigidBody3D in _props:
		var sample: Dictionary = _props[body]
		if not body.global_transform.is_equal_approx(sample.current):
			reset(body) # Also catch deferred placement after this frame's _process.
		if sample.submitted != null and sample.visual.is_equal_approx(sample.submitted) \
				and sample.visual.is_equal_approx(body.global_transform):
			continue # Native transforms suffice once a resting pose has been submitted.
		var correction: Transform3D = sample.visual * body.global_transform.affine_inverse()
		for mesh: MeshInstance3D in sample.meshes:
			# Flush native inherited transforms first; submit presentation after them.
			# Hidden damage-state meshes retain normal visibility and authored paths.
			mesh.force_update_transform()
			RenderingServer.instance_set_transform(mesh.get_instance(), correction * mesh.global_transform)
		sample.submitted = sample.visual


func _clear_pose(body: RigidBody3D, pose: Transform3D, current: Transform3D, previous: Transform3D) -> Transform3D:
	if pose.is_equal_approx(current):
		return pose
	# Rotating a supported box/monitor between two safe endpoints can put a corner
	# below its support. Do not add penetration into static walls/furniture/floors.
	# Existing solver contact tolerance is allowed, without changing collisions.
	for owner_id in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner_id):
			continue
		var local := body.shape_owner_get_transform(owner_id)
		for index in body.shape_owner_get_shape_count(owner_id):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner_id, index)
			query.collision_mask = 1 # Static World; dynamic props share the same render clock.
			query.margin = 0.0
			var space := body.get_world_3d().direct_space_state
			query.transform = pose * local
			var depth := _depth(space, query)
			if depth <= 0.002:
				continue
			query.transform = current * local
			var allowed := _depth(space, query)
			query.transform = previous * local
			allowed = maxf(allowed, _depth(space, query))
			if depth > allowed + 0.002:
				return current
	return pose


func _depth(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> float:
	var contacts := space.collide_shape(query, 8)
	var depth := 0.0
	for index in range(0, contacts.size(), 2):
		depth = maxf(depth, contacts[index].distance_to(contacts[index + 1]))
	return depth


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		for body: RigidBody3D in _props:
			var sample: Dictionary = _props[body]
			var frozen: Transform3D = sample.visual
			var teleported := not body.global_transform.is_equal_approx(sample.current)
			reset(body)
			if not teleported:
				sample.resume = frozen
				sample.elapsed = 0.0
