class_name ImpactDebris
extends RigidBody3D

# Collision protection only. Debris never receives damage or creates fragments.
var _sweep := PropMotionSweep.new()
var _rest_seconds: float = 0.0
var _settling: bool = false
var _held: bool = false


func set_held(held: bool) -> void:
	_held = held
	_rest_seconds = 0.0
	_set_settling(false)


func _init() -> void:
	# A 4 cm shard needs protection even below the ordinary 2 m/s cutoff.
	_sweep.minimum_speed = 0.2
	_sweep.contact_overlap = 0.002
	max_contacts_reported = 4


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
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
