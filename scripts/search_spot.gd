class_name SearchSpot
extends Marker3D

enum Category { SURFACE, OCCLUDED, LOW_UNDER, BEHIND, HIGH }

@export var search_category: Category = Category.SURFACE
@export var enabled: bool = true
@export var accepted_categories: PackedStringArray = ["small_personal"]


func accepts(item: TargetItem) -> bool:
	return enabled and accepted_categories.has(String(item.category))


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
