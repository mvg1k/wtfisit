class_name ImpactBody
extends RigidBody3D

signal damage_state_changed(body: ImpactBody)

enum State { INTACT, CRACKED, BROKEN }

const CONTACT_LIMIT: int = 8
const SWEEP_HINT_TICKS: int = 3
const DAMAGE_COOLDOWN_SECONDS: float = 0.3
const MIN_REPORTED_SEVERITY: float = 0.5

@export var impact_material: ImpactMaterial
@export var intact_visual: Node3D
@export var cracked_visual: Node3D
@export var broken_visual: Node3D
@export var fragment_extent := Vector3(0.38, 0.4, 0.38)
@export var fragment_material: Material

var damage_state: State = State.INTACT
var last_impact_severity: float = 0.0
var last_closing_speed: float = 0.0
var last_effective_mass: float = 0.0
var last_impact_source: String = "-"
var _motion_sweep := PropMotionSweep.new()
var _touching: Array[RID] = []
var _swept_contacts: Dictionary = {}
var _next_damage_frame: int = 0
var _transition_pending: bool = false


func _ready() -> void:
	# Only opted-in props report contacts. No process loop or world-wide polling.
	max_contacts_reported = CONTACT_LIMIT
	_refresh_visuals()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Falling, dropped and dead impact props need the same protection as throws.
	# Sleeping bodies do not run a separate frame loop.
	var incoming_velocity := state.linear_velocity
	var limited_velocity := _motion_sweep.limit_velocity(self, incoming_velocity, state.step)
	if not limited_velocity.is_equal_approx(incoming_velocity):
		state.linear_velocity = limited_velocity
	if impact_material == null or damage_state == State.BROKEN:
		return
	var frame := Engine.get_physics_frames()
	for rid: RID in _swept_contacts.keys():
		if frame > int(_swept_contacts[rid].expires):
			_swept_contacts.erase(rid)
	var contacts: Array[RID] = []
	var strongest := 0.0
	var strongest_speed := 0.0
	var strongest_source := "contact"
	for index in state.get_contact_count():
		var rid := state.get_contact_collider(index)
		contacts.append(rid)
		if _touching.has(rid):
			continue
		# Godot Physics reports these contact velocities/normals in world space.
		var relative := state.get_contact_local_velocity_at_position(index) \
			- state.get_contact_collider_velocity_at_position(index)
		var speed := maxf(0.0, -relative.dot(state.get_contact_local_normal(index)))
		var other := state.get_contact_collider_object(index)
		var severity := 0.0
		var source := "contact"
		if speed >= impact_material.minimum_closing_speed:
			severity = ImpactMaterial.severity(mass, _dynamic_mass(other), speed)
		# Sweep hints are consumed only by a real contact with that same collider.
		if _swept_contacts.has(rid):
			if float(_swept_contacts[rid].severity) > severity:
				severity = float(_swept_contacts[rid].severity)
				speed = float(_swept_contacts[rid].speed)
				source = "confirmed sweep"
		if severity > strongest:
			strongest = severity
			strongest_speed = speed
			strongest_source = source
	for rid in contacts:
		_swept_contacts.erase(rid)
	_touching = contacts
	if strongest < MIN_REPORTED_SEVERITY:
		return
	last_impact_severity = strongest
	last_closing_speed = strongest_speed
	last_effective_mass = 2.0 * strongest / (strongest_speed * strongest_speed)
	last_impact_source = strongest_source
	if _transition_pending or frame < _next_damage_frame:
		return
	var threshold := impact_material.damage_threshold if damage_state == State.INTACT else impact_material.break_threshold
	if impact_material.brittle:
		threshold = impact_material.break_threshold
	if strongest < threshold:
		return
	# At most one authored state change per impact; cooldown suppresses bounce
	# clusters. Weak contacts never accumulate invisible attrition.
	damage_state = State.BROKEN if impact_material.brittle or damage_state == State.CRACKED else State.CRACKED
	_next_damage_frame = frame + ceili(DAMAGE_COOLDOWN_SECONDS * Engine.physics_ticks_per_second)
	_transition_pending = true
	_commit_state.call_deferred()


func _commit_state() -> void:
	if not is_inside_tree():
		return
	_transition_pending = false
	damage_state_changed.emit(self)
	if damage_state == State.BROKEN and impact_material.brittle:
		# Remove the intact collider before adding non-overlapping fragments.
		collision_layer = 0
		collision_mask = 0
		ImpactFragments.spawn(get_parent(), global_transform, fragment_extent, mass,
			linear_velocity, angular_velocity, fragment_material, impact_material.kind == ImpactMaterial.Kind.GLASS)
		queue_free()
	else:
		_refresh_visuals()
		if damage_state == State.BROKEN:
			max_contacts_reported = 4 # Rest support only; damage processing returns early.
			_swept_contacts.clear()
			_touching.clear()


func _refresh_visuals() -> void:
	if is_instance_valid(intact_visual):
		intact_visual.visible = damage_state == State.INTACT
	if is_instance_valid(cracked_visual):
		cracked_visual.visible = damage_state == State.CRACKED
	if is_instance_valid(broken_visual):
		broken_visual.visible = damage_state == State.BROKEN


static func _dynamic_mass(body: Object) -> float:
	return body.mass if body is RigidBody3D and not body.freeze else 0.0


static func remember_sweep(body: RigidBody3D, result: PhysicsTestMotionResult3D, velocity: Vector3) -> void:
	# The grabber's safety sweep clips travel speed. Retain only imminent contact
	# severity, not a damage event, without changing its collision response.
	var direct_state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var center := body.global_position
	if direct_state != null:
		center = direct_state.transform * direct_state.center_of_mass_local
	var spin: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	for index in result.get_collision_count():
		var other := result.get_collider(index)
		if not body is ImpactBody and not other is ImpactBody:
			continue
		var point := result.get_collision_point(index)
		# Angular contact speed is measured about the physical center of mass,
		# which need not coincide with an authored pivot (the monitor's feet).
		var relative := velocity + spin.cross(point - center) - result.get_collider_velocity(index)
		var speed := maxf(0.0, -relative.dot(result.get_collision_normal(index)))
		var severity := ImpactMaterial.severity(body.mass, _dynamic_mass(other), speed)
		if body is ImpactBody:
			body._remember_contact(result.get_collider_rid(index), speed, severity)
		if other is ImpactBody:
			other._remember_contact(body.get_rid(), speed, severity)


func _remember_contact(rid: RID, speed: float, severity: float) -> void:
	if impact_material == null or damage_state == State.BROKEN or speed < impact_material.minimum_closing_speed:
		return
	# Bound the tiny cache even if a sleeping target receives many near misses.
	if _swept_contacts.size() >= CONTACT_LIMIT and not _swept_contacts.has(rid):
		_swept_contacts.erase(_swept_contacts.keys()[0])
	var previous: Dictionary = _swept_contacts.get(rid, {})
	if not previous.is_empty() and int(previous.expires) >= Engine.get_physics_frames():
		if float(previous.severity) > severity:
			severity = float(previous.severity)
			speed = float(previous.speed)
	_swept_contacts[rid] = {"severity": severity, "speed": speed, "expires": Engine.get_physics_frames() + SWEEP_HINT_TICKS}
