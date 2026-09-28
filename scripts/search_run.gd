class_name SearchRun
extends Node3D

signal state_changed

enum State { PREPARING, SEARCHING, COMPLETED, UNAVAILABLE }

@export var room_scene: PackedScene
@export var target_scene: PackedScene

var state: State = State.PREPARING
var room: SearchRoom
var target: TargetItem
var current_spot: SearchSpot
var target_name: String = "KEYS"
var error_message: String = ""
var debug_search_visible: bool = false
var elapsed_seconds: float:
	get:
		if state == State.SEARCHING:
			return float(Time.get_ticks_usec() - _started_at_usec) / 1000000.0
		return _completion_seconds

var _rng := RandomNumberGenerator.new()
var _recent_spots: Array[StringName] = []
var _recent_categories: Array[int] = []
var _started_at_usec: int = 0
var _completion_seconds: float = 0.0
var _starting: bool = false


func _ready() -> void:
	_rng.randomize()
	start_run.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("toggle_search_debug"):
		debug_search_visible = not debug_search_visible
		state_changed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_search") and state in [State.COMPLETED, State.UNAVAILABLE]:
		start_run.call_deferred()
		get_viewport().set_input_as_handled()
	elif OS.is_debug_build() and debug_search_visible and event.is_action_pressed("debug_new_search"):
		start_run.call_deferred()
		get_viewport().set_input_as_handled()


func start_run() -> void:
	if _starting:
		return
	_starting = true
	state = State.PREPARING
	_completion_seconds = 0.0
	error_message = ""
	target = null
	current_spot = null
	state_changed.emit()
	if is_instance_valid(room):
		room.grabber.release()
		remove_child(room)
		room.queue_free()
		room = null
	if room_scene == null or target_scene == null:
		_fail("Missing room or target scene.")
		return
	var room_node := room_scene.instantiate()
	if not room_node is SearchRoom:
		room_node.free()
		_fail("Invalid room scene.")
		return
	room = room_node as SearchRoom
	add_child(room)
	# Wait for new colliders to register before rejecting obstructed spots.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var item_node := target_scene.instantiate()
	if not item_node is TargetItem:
		item_node.free()
		_fail("Invalid target scene.")
		return
	var item := item_node as TargetItem
	target_name = item.display_name
	var candidates := room.valid_spots(item)
	if candidates.is_empty():
		item.free()
		_fail("No clear, compatible search spots are available.")
		return
	current_spot = _choose_spot(candidates)
	target = item
	room.add_child(target)
	target.global_transform = current_spot.global_transform
	room.grabber.object_picked_up.connect(_on_object_picked_up)
	_started_at_usec = Time.get_ticks_usec()
	state = State.SEARCHING
	_starting = false
	state_changed.emit()


func _choose_spot(candidates: Array[SearchSpot]) -> SearchSpot:
	var categories: Array[int] = []
	for spot in candidates:
		if not categories.has(spot.search_category):
			categories.append(spot.search_category)
	var fresh_categories := categories.filter(func(category: int) -> bool:
		return not _recent_categories.has(category))
	if fresh_categories.is_empty():
		fresh_categories = categories.filter(func(value: int) -> bool:
			return _recent_categories.is_empty() or value != _recent_categories.back())
	if fresh_categories.is_empty():
		fresh_categories = categories
	var category: int = fresh_categories[_rng.randi_range(0, fresh_categories.size() - 1)]
	var choices := candidates.filter(func(spot: SearchSpot) -> bool:
		return spot.search_category == category)
	var fresh_spots := choices.filter(func(spot: SearchSpot) -> bool:
		return not _recent_spots.has(spot.name))
	if fresh_spots.is_empty():
		# With a small pool, still avoid an immediate repeat whenever possible.
		fresh_spots = choices.filter(func(spot: SearchSpot) -> bool:
			return _recent_spots.is_empty() or spot.name != _recent_spots.back())
	if fresh_spots.is_empty():
		fresh_spots = choices
	var selected: SearchSpot = fresh_spots[_rng.randi_range(0, fresh_spots.size() - 1)]
	_recent_categories.append(category)
	_recent_spots.append(selected.name)
	if _recent_categories.size() > 2:
		_recent_categories.pop_front()
	if _recent_spots.size() > 3:
		_recent_spots.pop_front()
	return selected


func _on_object_picked_up(body: RigidBody3D) -> void:
	if state != State.SEARCHING or body != target:
		return
	_completion_seconds = elapsed_seconds
	state = State.COMPLETED
	state_changed.emit()


func _fail(message: String) -> void:
	error_message = message
	state = State.UNAVAILABLE
	_starting = false
	state_changed.emit()
