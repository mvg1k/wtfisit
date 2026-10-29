extends CanvasLayer

@export var grabber: PhysicsGrabber
@export var debug_visible: bool = true
@onready var _stats: Label = %Stats
var _elapsed: float = 0.0


func _ready() -> void:
	%ThrowChargeIndicator.grabber = grabber
	_stats.visible = debug_visible
	_update_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
		_stats.visible = debug_visible
		_update_stats()


func _process(delta: float) -> void:
	# Crosshair/ring use their native screen-centre anchors. Projecting a physics
	# hit through the interpolated view makes these controls oscillate every tick.
	if not debug_visible:
		return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		_update_stats()


func _update_stats() -> void:
	var body := grabber.held_body
	var detail := "Held: no"
	if is_instance_valid(body):
		detail = "Held: yes\n%s | %.2f kg" % [body.name, body.mass]
		detail += "\nHold distance: %.2f m" % grabber.current_hold_distance
		if OS.is_debug_build():
			var hold := grabber.get_hold_diagnostics()
			detail += " requested | actual centre: %.2f m\nPivot: %.2f m | visual centre: %.2f m" % [
				hold.actual_distance, hold.pivot_distance, hold.visual_distance]
			detail += "\nTarget: %s (%.2f m) | error: %.2f m\nLocal centre: %s" % [
				hold.target_position, hold.target_distance, hold.target_error, hold.local_center]
			detail += "\nClearance: %s | contacts: %d\nSight blocked: %s | player overlap: %s | target limited: %s" % [
				hold.clearance_collider, hold.solver_contacts, hold.sight_blocked, hold.player_overlap, hold.player_limited_target]
			detail += "\nCurrent penetration: %.1f mm | padding: %s\nProposed target overlap: %s | recovery: %s (%s)" % [
				hold.current_depth * 1000, hold.padded_overlap, hold.target_overlap, hold.recovery_active, hold.recovery_direction]
		if OS.is_debug_build() and grabber.is_charging_throw:
			detail += "\nThrow: %d%%" % roundi(grabber.throw_charge * 100.0)
		if OS.is_debug_build() and body is ImpactBody and body.impact_material != null:
			detail += "\n%s | %s\nLast impact: %.1f | thresholds: %.0f / %.0f" % [
				ImpactMaterial.Kind.keys()[body.impact_material.kind], ImpactBody.State.keys()[body.damage_state],
				body.last_impact_severity, body.impact_material.damage_threshold, body.impact_material.break_threshold]
			detail += "\nClosing: %.2f m/s | effective mass: %.2f kg\n%s" % [
				body.last_closing_speed, body.last_effective_mass, body.last_impact_source]
	if OS.is_debug_build():
		if not is_instance_valid(body):
			var pickup := grabber.get_pickup_diagnostics()
			var distance := "--" if pickup.surface_distance < 0 else "%.3f m" % pickup.surface_distance
			detail += "\nAim: %s → %s\nSurface: %s / %.2f m | pickup: %s (%s)" % [
				pickup.aimed_collider, pickup.pickup_body, distance, grabber.reach, pickup.eligible, pickup.reason]
			detail += "\nOccluder: %s | player overlap: %s | E queued: %s" % [
				pickup.occluder, pickup.player_overlap, pickup.input_queued]
			detail += "\nCurrent penetration: %.1f mm | padding: %s\nPreferred target overlap: %s | escape: %s" % [
				pickup.current_depth * 1000, pickup.padded_overlap, pickup.target_overlap, pickup.recovery_rejection]
			detail += "\nRecovery path: %s | candidates checked: %d / 7" % [pickup.recovery_direction, pickup.recovery_candidates]
		if not grabber.last_pickup_attempt.is_empty():
			var attempt := grabber.last_pickup_attempt
			detail += "\nPickup #%d: %s → %s (tick %d)" % [
				grabber.pickup_attempts, attempt.reason, attempt.outcome, attempt.physics_frame]
		if not grabber.last_release.is_empty():
			detail += "\nLast release: %s — %s (tick %d)" % [
				grabber.last_release.body, grabber.last_release.reason, grabber.last_release.physics_frame]
		var hit := grabber.get_kick_target()
		var target := "none"
		if is_instance_valid(body):
			target = "unavailable (holding)"
		elif not hit.is_empty():
			target = "%s (%.2f m foot)" % [hit.collider.name, hit.distance]
		detail += "\nKick target: %s\nKick range: %.2f m max" % [target, grabber.kick_reach]
		if not hit.is_empty():
			detail += "\nContact height: %+.2f m above feet" % hit.contact_height
	_stats.text = "FPS: %d\n%s\nStance: %s" % [
		Engine.get_frames_per_second(), detail, SandboxPlayer.Stance.keys()[grabber.player.stance]]
