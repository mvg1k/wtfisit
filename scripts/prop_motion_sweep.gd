class_name PropMotionSweep
extends RefCounted

const CONTACT_OVERLAP: float = 0.01
var minimum_speed: float = 2.0
var contact_overlap: float = CONTACT_OVERLAP
var _query := PhysicsTestMotionParameters3D.new()
var _result := PhysicsTestMotionResult3D.new()


func limit_velocity(body: RigidBody3D, velocity: Vector3, delta: float,
		excluded: Array[RID] = []) -> Vector3:
	if velocity.length_squared() < minimum_speed * minimum_speed:
		return velocity
	_query.from = body.global_transform
	_query.motion = velocity * delta
	_query.margin = 0.001
	_query.exclude_bodies = excluded
	if not PhysicsServer3D.body_test_motion(body.get_rid(), _query, _result):
		return velocity
	ImpactBody.remember_sweep(body, _result, velocity)
	# One millimetre could leave a rotating body outside the contact manifold:
	# it would creep forward after CCD clipped its speed, outliving the impact hint.
	# A solver-sized overlap establishes contact on the next step. No teleport.
	var travel := _result.get_collision_unsafe_fraction() * _query.motion.length()
	return velocity.normalized() * minf(velocity.length(), (travel + contact_overlap) / delta)
