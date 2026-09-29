class_name SearchRoom
extends Node3D

@export var grabber: PhysicsGrabber
@export var spots_root: Node3D

var spawn_eye: Vector3
var spawn_frustum: Array[Plane] = []


func _ready() -> void:
	# Snapshot before preparation waits or input can move the initial viewpoint.
	spawn_eye = grabber.camera.global_position
	spawn_frustum = grabber.camera.get_frustum()


func hidden_from_spawn(spots: Array[SearchSpot], item: TargetItem) -> Array[SearchSpot]:
	var result: Array[SearchSpot] = []
	for spot in spots:
		if not spot.clearly_visible_from_spawn(item, spawn_eye, spawn_frustum):
			result.append(spot)
	return result


func valid_spots(item: TargetItem) -> Array[SearchSpot]:
	var result: Array[SearchSpot] = []
	for node in spots_root.get_children():
		if node is SearchSpot and node.can_place(item):
			result.append(node)
	return result
