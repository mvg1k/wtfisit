class_name SearchSpot
extends Marker3D

enum Category { SURFACE, OCCLUDED, LOW_UNDER, BEHIND, HIGH }
enum Action { VISUAL_SEARCH, CROUCH, PRONE, MOVE_PROP, CLIMB }

@export var search_category: Category = Category.SURFACE
@export var intended_action: Action = Action.VISUAL_SEARCH
@export var enabled: bool = true
@export var accepted_categories: PackedStringArray = ["small_personal"]


func accepts(item: TargetItem) -> bool:
	return enabled and Category.values().has(search_category) and Action.values().has(intended_action) \
		and accepted_categories.has(String(item.category))


func clearly_visible_from_spawn(item: TargetItem, eye: Vector3, frustum: Array[Plane]) -> bool:
	# Sample each collider's center and inset corners. This is only an exposure
	# veto, not a difficulty score. Partial occlusion stays eligible.
	var sampled := false
	for owner_id: int in item.get_shape_owners():
		if item.is_shape_owner_disabled(owner_id):
			continue
		for index in item.shape_owner_get_shape_count(owner_id):
			var shape := item.shape_owner_get_shape(owner_id, index)
			var bounds := shape.get_debug_mesh().get_aabb()
			var placement := global_transform * item.shape_owner_get_transform(owner_id)
			var center := bounds.get_center()
			var samples: Array[Vector3] = [center]
			for corner in 8:
				samples.append(center.lerp(bounds.get_endpoint(corner), 0.7))
			for sample in samples:
				var point := placement * sample
				for plane in frustum:
					if plane.is_point_over(point):
						return false
				var ray := PhysicsRayQueryParameters3D.create(eye, point, 1 | 4)
				ray.exclude = [item.get_rid()]
				if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
					return false
				sampled = true
	return sampled


func can_place(item: TargetItem) -> bool:
	if not accepts(item):
		return false
	# Only checked at run start, after the room has entered the physics world.
	var space := get_world_3d().direct_space_state
	for owner_id: int in item.get_shape_owners():
		if item.is_shape_owner_disabled(owner_id):
			continue
		for index in item.shape_owner_get_shape_count(owner_id):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = item.shape_owner_get_shape(owner_id, index)
			query.transform = global_transform * item.shape_owner_get_transform(owner_id)
			query.collision_mask = 7
			query.margin = 0.002
			if not space.intersect_shape(query, 1).is_empty():
				return false
	return true
