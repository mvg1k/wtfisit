class_name ImpactFragments
extends RefCounted

const MAX_PIECES: int = 4
# Fixed four-piece authored breakup pattern; no mesh cutting or recursive script.
const OFFSETS: Array[Vector3] = [Vector3(-0.25, -0.05, -0.25), Vector3(0.25, -0.05, -0.25),
	Vector3(-0.25, -0.05, 0.25), Vector3(0.25, -0.05, 0.25)]


static func spawn(parent: Node, placement: Transform3D, extent: Vector3, total_mass: float,
		linear: Vector3, angular: Vector3, material: Material, glass: bool = false) -> void:
	var surface := PhysicsMaterial.new()
	surface.friction = 0.65
	surface.bounce = 0.0
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
		# No explosion impulse; caps avoid energetic micro-debris and chain reactions.
		piece.linear_velocity = (linear + angular.cross(offset)).limit_length(6.0)
		piece.angular_velocity = angular.limit_length(7.0)


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
