class_name SearchRoom
extends Node3D

@export var grabber: PhysicsGrabber
@export var spots_root: Node3D


func valid_spots(item: TargetItem) -> Array[SearchSpot]:
	var result: Array[SearchSpot] = []
	for node in spots_root.get_children():
		if node is SearchSpot and node.can_place(item):
			result.append(node)
	return result
