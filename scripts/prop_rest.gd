class_name PropRest
extends Node

# Godot's contact corrections can repeatedly reset velocity-only sleep tests
# even when a supported prop has stayed in the same small pose envelope.
# Track only awake grabbable bodies; never damp motion or freeze a body.
const QUIET_SECONDS: float = 1.0
const POSITION_TOLERANCE: float = 0.03
const ANGLE_TOLERANCE: float = 0.18
var grabber: PhysicsGrabber
var _awake: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_node_added)
	_register_existing.call_deferred()


func _register_existing() -> void:
	for body in get_tree().get_nodes_in_group("grabbable"):
		_register(body)


func _node_added(node: Node) -> void:
	if node is RigidBody3D:
		_register.call_deferred(node)


func _register(node: Variant) -> void:
	if not is_instance_valid(node) or not is_instance_valid(grabber) or not grabber.is_inside_tree():
		return
	var body := node as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.is_in_group("grabbable"):
		return
	if body.get_world_3d() != grabber.get_world_3d():
		return
	var callback := _sleep_changed.bind(body)
	if body.sleeping_state_changed.is_connected(callback):
		return
	body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
	body.sleeping_state_changed.connect(callback)
	body.tree_exiting.connect(_unregister.bind(body))
	_sleep_changed(body)


func _sleep_changed(body: RigidBody3D) -> void:
	if body.sleeping:
		_awake.erase(body)
	elif not _awake.has(body):
		track_awake(body)


func track_awake(body: RigidBody3D) -> void:
	_register(body)
	_awake[body] = {"pose": body.global_transform, "time": 0.0}


func _unregister(body: RigidBody3D) -> void:
	_awake.erase(body)


func _physics_process(delta: float) -> void:
	# A kinematic push is applied before this callback. Never consume that
	# impulse while confirming a quiet island, even for a slow heavy prop.
	var player_contacts: Dictionary = {}
	for slide in grabber.player.get_slide_collision_count():
		var collision := grabber.player.get_slide_collision(slide)
		for index in collision.get_collision_count():
			var collider := collision.get_collider(index)
			if collider is RigidBody3D:
				player_contacts[collider] = true
	for key: Variant in _awake.keys():
		if not is_instance_valid(key):
			_awake.erase(key)
			continue
		var body := key as RigidBody3D
		var sample: Dictionary = _awake[body]
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null:
			continue
		if state.sleeping:
			# Confirm sleep after the solver has had a chance to wake the island.
			# A single quiet body may wake again while its neighbour is settling.
			sample["sleep_frames"] = int(sample.get("sleep_frames", 0)) + 1
			if sample.sleep_frames >= 3:
				_awake.erase(body)
			continue
		sample["sleep_frames"] = 0
		var supported := false
		var disturbed := false
		for index in state.get_contact_count():
			supported = supported or state.get_contact_local_normal(index).y > 0.5
			disturbed = disturbed or state.get_contact_collider_velocity_at_position(index).length() > 0.4
		var anchor: Transform3D = sample.pose
		var quiet := supported and not disturbed and not player_contacts.has(body) \
			and body != grabber.held_body and not body.freeze and body.can_sleep \
			and body.constant_force.is_zero_approx() and body.constant_torque.is_zero_approx() \
			and state.linear_velocity.length() < 0.4 and state.angular_velocity.length() < 1.5 \
			and state.transform.origin.distance_to(anchor.origin) < POSITION_TOLERANCE \
			and state.transform.basis.get_rotation_quaternion().angle_to(anchor.basis.get_rotation_quaternion()) < ANGLE_TOLERANCE
		if not quiet:
			sample.pose = state.transform
			sample.time = 0.0
			continue
		sample.time += delta
		if sample.time >= QUIET_SECONDS:
			# Normal dynamic sleep: contacts, impulses and pickup still wake it.
			body.sleeping = true
