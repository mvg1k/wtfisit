class_name ImpactDebris
extends RigidBody3D

const MAX_BOUNCE_SPEED: float = 0.9

# Bounded fragment response and collision protection; no damage or recursive breakup.
var _sweep := PropMotionSweep.new()
var _rest_seconds: float = 0.0
var _settling: bool = false
var _held: bool = false
var _scatter_linear := Vector3.ZERO
var _scatter_angular := Vector3.ZERO
var _scatter_pending: bool = false
var _bounce_rid := RID()
var _bounce_speed: float = 0.0
var _bounce_expires: int = 0


func queue_scatter(linear_change: Vector3, angular_change: Vector3) -> void:
	_scatter_linear = linear_change
	_scatter_angular = angular_change
	_scatter_pending = true


func set_held(held: bool) -> void:
	_held = held
	_bounce_rid = RID()
	_rest_seconds = 0.0
	_set_settling(false)


func remember_bounce(result: PhysicsTestMotionResult3D, velocity: Vector3) -> void:
	if _held:
		return
	for index in mini(result.get_collision_count(), 4):
		var speed := maxf(0.0, -velocity.dot(result.get_collision_normal(index)))
		if speed > 0.75 and (Engine.get_physics_frames() > _bounce_expires or speed > _bounce_speed):
			_bounce_rid = result.get_collider_rid(index)
			_bounce_speed = speed
			_bounce_expires = Engine.get_physics_frames() + 3


func _init() -> void:
	# A 4 cm shard needs protection even below the ordinary 2 m/s cutoff.
	_sweep.minimum_speed = 0.2
	_sweep.contact_overlap = 0.002
	max_contacts_reported = 4


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _scatter_pending:
		_scatter_pending = false
		# Spawned bodies initialize mass/inertia before this first physics callback.
		# Applying impulses at add_child time uses stale inverse mass in Godot.
		var velocity := (state.linear_velocity + _scatter_linear).limit_length(ImpactFragments.MAX_LINEAR_SPEED)
		if state.inverse_mass > 0.0:
			state.apply_central_impulse((velocity - state.linear_velocity) / state.inverse_mass)
		var spin := (state.angular_velocity + _scatter_angular).limit_length(ImpactFragments.MAX_ANGULAR_SPEED)
		if absf(state.inverse_inertia_tensor.determinant()) > 0.000001:
			state.apply_torque_impulse(state.inverse_inertia_tensor.inverse() * (spin - state.angular_velocity))
	# The safety sweep clips incoming speed before the solver sees it. Restore
	# only modest restitution after a real matching contact, never on a prediction.
	if _bounce_rid.is_valid() and Engine.get_physics_frames() <= _bounce_expires:
		for index in state.get_contact_count():
			if state.get_contact_collider(index) != _bounce_rid:
				continue
			var normal := state.get_contact_local_normal(index)
			var bounce := physics_material_override.bounce if physics_material_override != null else 0.0
			var target := minf(_bounce_speed * bounce, MAX_BOUNCE_SPEED)
			var added := maxf(0.0, target - state.linear_velocity.dot(normal))
			if state.inverse_mass > 0.0:
				state.apply_central_impulse(normal * added / state.inverse_mass)
			_bounce_rid = RID()
			break
	# Small edge contacts can generate excessive spin after the initial cap.
	if state.angular_velocity.length_squared() > 49.0:
		state.angular_velocity = state.angular_velocity.limit_length(7.0)
	# Keep protecting substantial motion even while touching another surface.
	# Let the solver own quiet manifolds: repeatedly clipping resting gravity
	# velocity can itself keep an island awake.
	if state.get_contact_count() == 0 or state.linear_velocity.length_squared() > 1.0 \
			or state.angular_velocity.length_squared() > 16.0:
		var limited := _sweep.limit_velocity(self, state.linear_velocity, state.step)
		if not limited.is_equal_approx(state.linear_velocity):
			state.linear_velocity = limited
	if _held:
		return # The grabber owns damping until release.
	# Thin shards can rock around alternating edge contacts at the solver's
	# normal 1 cm slop. Dissipate only small supported residual motion; free
	# flight, substantial impacts and moving supports retain ordinary dynamics.
	var supported := false
	for index in state.get_contact_count():
		if state.get_contact_local_normal(index).y > 0.6 and state.get_contact_collider_velocity_at_position(index).length() < 0.1:
			supported = true
	var quiet := supported and state.linear_velocity.length() < 0.4 and state.angular_velocity.length() < 4.0
	_rest_seconds = _rest_seconds + state.step if quiet else 0.0
	var settle := _rest_seconds > 0.25 or (_settling and supported
		and state.linear_velocity.length() < 1.0 and state.angular_velocity.length() < 6.0)
	_set_settling(settle)


func _set_settling(settle: bool) -> void:
	if settle != _settling:
		_settling = settle
		# Change damping only on entry/exit. Writing even tiny velocities every
		# frame wakes the body and defeats the engine's normal sleep timer.
		linear_damp = 2.0 if settle else 0.5
		angular_damp = 12.0 if settle else 2.0
