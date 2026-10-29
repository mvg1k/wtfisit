class_name ImpactFragments
extends RefCounted

const MAX_PIECES: int = 4
const MAX_LINEAR_SPEED: float = 6.0
const MAX_ANGULAR_SPEED: float = 7.0
const SCATTER_ENERGY_FRACTION: float = 0.06
# Fixed four-piece authored breakup pattern; no mesh cutting or recursive script.
const OFFSETS: Array[Vector3] = [Vector3(-0.25, -0.05, -0.25), Vector3(0.25, -0.05, -0.25),
	Vector3(-0.25, -0.05, 0.25), Vector3(0.25, -0.05, 0.25)]


static func spawn(parent: Node, placement: Transform3D, extent: Vector3, total_mass: float,
		linear: Vector3, angular: Vector3, material: Material, glass: bool = false,
		visual_source: RigidBody3D = null, response: ImpactMaterial = null, impact: Dictionary = {}) -> void:
	var surface := PhysicsMaterial.new()
	surface.friction = 0.65
	surface.bounce = response.fragment_bounce if response != null else 0.1
	var occupied: Array[AABB] = []
	for index in MAX_PIECES:
		# Authored flat shard silhouettes, not a fracture algorithm. A matching
		# convex prism gives each piece a stable face to rest on.
		var vertices := _shard_vertices(extent, index, glass)
		var shape := ConvexPolygonShape3D.new()
		# Godot Physics ignores Shape3D.margin. Give these centimetre-scale
		# shards an explicit 1 cm collision skin, matching its contact tolerance.
		# Otherwise that tolerance consumes a quarter of a thin glass shard.
		var collision_vertices := PackedVector3Array()
		for point in vertices:
			collision_vertices.append(point + point.sign() * 0.01)
		shape.points = collision_vertices
		var mesh := _shard_mesh(vertices, material)
		var piece := ImpactDebris.new()
		piece.name = "Fragment"
		piece.add_to_group("impact_debris")
		piece.add_to_group("grabbable")
		piece.mass = total_mass / MAX_PIECES
		# Four times box inertia damps the solver's edge-contact spin response on
		# tiny shards while preserving free rotation, contact bounce and sleeping.
		var size := shape.get_debug_mesh().get_aabb().size
		piece.inertia = Vector3(size.y * size.y + size.z * size.z,
			size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) * piece.mass / 3.0
		piece.collision_layer = 4
		piece.collision_mask = 5
		piece.continuous_cd = true
		piece.linear_damp = 0.5
		piece.angular_damp = 2.0
		piece.physics_material_override = surface
		var collision := CollisionShape3D.new()
		collision.shape = shape
		piece.add_child(collision)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		piece.add_child(visual)
		var offset := placement.basis * (OFFSETS[index] * extent)
		var world_placement := placement
		world_placement.origin += offset
		var placements := _clear_placement(parent.get_world_3d().direct_space_state, shape, world_placement, occupied)
		if placements.is_empty():
			# An enclosed space need not have room for every authored piece.
			# Never insert an intersecting body and ask the solver to explode it out.
			piece.free()
			continue
		world_placement = placements[0]
		occupied.append((world_placement * shape.get_debug_mesh().get_aabb()).grow(0.002))
		# Install the final transform before entering the physics world; also
		# handle a transformed room parent without briefly spawning at its origin.
		piece.transform = (parent.global_transform.affine_inverse() * world_placement
			if parent is Node3D else world_placement)
		parent.add_child(piece)
		# Post-contact motion, including tangential motion from the old body's spin.
		piece.linear_velocity = (linear + angular.cross(offset)).limit_length(MAX_LINEAR_SPEED)
		piece.angular_velocity = angular.limit_length(MAX_ANGULAR_SPEED)
		_scatter(piece, index, placement.origin, total_mass, linear, response, impact)
		if is_instance_valid(visual_source) and visual_source.has_meta("prop_visual_interpolation"):
			var reference: WeakRef = visual_source.get_meta("prop_visual_interpolation")
			var visuals := reference.get_ref() as PropVisualInterpolation
			if is_instance_valid(visuals):
				visuals.seed_replacement(piece, visual_source)


static func _scatter(piece: ImpactDebris, index: int, origin: Vector3, total_mass: float,
		incoming: Vector3, response: ImpactMaterial, impact: Dictionary) -> void:
	var threshold := response.break_threshold if response != null else 10.0
	var severity := maxf(0.0, float(impact.get("severity", threshold)))
	var strength := clampf(sqrt(severity / maxf(threshold, 0.1)), 0.0, 2.0)
	var scatter_speed := response.fragment_scatter_speed if response != null else 1.8
	var scatter_spin := response.fragment_scatter_spin if response != null else 3.5
	# Bound added translation by a small share of the measured impact energy,
	# plus material and total-speed caps. A harder hit never becomes an explosion.
	var speed := minf(scatter_speed * strength,
		sqrt(2.0 * severity * SCATTER_ENERGY_FRACTION / maxf(total_mass, 0.01)))
	var normal: Vector3 = impact.get("normal", Vector3.ZERO)
	normal = normal.normalized()
	var direction: Vector3 = impact.get("direction", incoming.normalized())
	if direction.is_zero_approx():
		direction = -normal if not normal.is_zero_approx() else Vector3.UP
	direction = direction.normalized()
	if not normal.is_zero_approx() and direction.dot(normal) < 0.0:
		direction = direction.bounce(normal) # Continue glancing motion, rebound from the surface.
	var point: Vector3 = impact.get("position", origin)
	var radial := piece.global_position - point
	if not normal.is_zero_approx():
		radial = radial.slide(normal)
	if radial.is_zero_approx():
		radial = Vector3.RIGHT.rotated(Vector3.UP, index * TAU / MAX_PIECES)
	radial = radial.normalized()
	var fan := (direction * 0.7 + radial * 0.65 + normal * 0.25).normalized()
	if not normal.is_zero_approx() and fan.dot(normal) < 0.15:
		fan = (fan.slide(normal) + normal * 0.15).normalized()
	# Different deterministic axes fan the four pieces without an RNG or new bodies.
	var axis := normal.cross(radial) + direction.cross(radial) * 0.3 \
		+ Vector3(0.4, -0.3 if index % 2 else 0.3, 0.2 if index < 2 else -0.2)
	axis = axis.normalized()
	piece.queue_scatter(fan * speed, axis * scatter_spin * strength)


static func _clear_placement(space: PhysicsDirectSpaceState3D, shape: Shape3D,
		placement: Transform3D, occupied: Array[AABB]) -> Array[Transform3D]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 5
	query.margin = 0.003
	# Resolve *before* insertion, not by teleporting a live rigid body. The
	# intact source already has layer/mask zero. Check sibling bounds explicitly:
	# newly added siblings may not yet be visible in the physics broad phase.
	var directions: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.LEFT,
		Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]
	# Corners and already placed siblings can block all six axial candidates.
	# Include diagonal exits within the same small placement radius.
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if absi(x) + absi(y) + absi(z) > 1:
					directions.append(Vector3(x, y, z).normalized())
	var bounds := shape.get_debug_mesh().get_aabb()
	for attempt in 1 + directions.size() * 4:
		var candidate := placement
		if attempt > 0:
			candidate.origin += directions[(attempt - 1) % directions.size()] * (1 + floorf((attempt - 1) / float(directions.size()))) * 0.06
		for iteration in 12:
			query.transform = candidate
			var contacts := space.collide_shape(query, 8)
			if contacts.is_empty():
				var overlaps_piece := false
				for other in occupied:
					overlaps_piece = overlaps_piece or other.intersects(candidate * bounds)
				if not overlaps_piece and space.intersect_shape(query, 1).is_empty():
					return [candidate]
				break
			var correction := Vector3.ZERO
			for pair in range(0, contacts.size(), 2):
				var separation := contacts[pair + 1] - contacts[pair]
				if separation.length_squared() > correction.length_squared():
					correction = separation
			if correction.length_squared() < 0.0000001:
				break
			candidate.origin += correction + correction.normalized() * 0.004
			if candidate.origin.distance_to(placement.origin) > 0.3:
				break
	return []


static func _shard_vertices(extent: Vector3, index: int, glass: bool) -> PackedVector3Array:
	# Four irregular quadrilaterals cut from a bottle/vase wall. Thickness is
	# deliberately exaggerated at prototype scale for reliable 60 Hz contacts.
	var outlines: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-0.46, -0.42), Vector2(0.42, -0.34), Vector2(0.30, 0.48), Vector2(-0.38, 0.24)]),
		PackedVector2Array([Vector2(-0.40, -0.30), Vector2(0.48, -0.44), Vector2(0.19, 0.46), Vector2(-0.46, 0.36)]),
		PackedVector2Array([Vector2(-0.44, -0.46), Vector2(0.30, -0.27), Vector2(0.46, 0.38), Vector2(-0.30, 0.46)]),
		PackedVector2Array([Vector2(-0.36, -0.32), Vector2(0.46, -0.46), Vector2(0.36, 0.28), Vector2(-0.46, 0.44)])]
	var vertices := PackedVector3Array()
	var thickness := 0.04 if glass else 0.065
	# A small authored bevel removes razor-edge contact pivots while retaining
	# the shard silhouette and broad flat resting faces.
	for ring in 4:
		var height: float = [-thickness * 0.5, -thickness * 0.5 + 0.006,
			thickness * 0.5 - 0.006, thickness * 0.5][ring]
		var width := 0.85 if ring == 0 or ring == 3 else 1.0
		for point in outlines[index]:
			vertices.append(Vector3(point.x * extent.x * 0.47 * width, height, point.y * extent.z * 0.47 * width))
	return vertices


static func _shard_mesh(vertices: PackedVector3Array, material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	# Flat faces retain sharp edges and a ceramic/glass appearance.
	var triangles: Array[int] = [0, 2, 1, 0, 3, 2, 12, 13, 14, 12, 14, 15]
	for ring in 3:
		for edge in 4:
			var a := ring * 4 + edge
			var b := ring * 4 + (edge + 1) % 4
			triangles.append_array([a, b + 4, a + 4, a, b, b + 4])
	for vertex in triangles:
		surface.add_vertex(vertices[vertex])
	surface.generate_normals()
	return surface.commit()
