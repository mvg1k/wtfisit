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
		if OS.is_debug_build() and grabber.is_charging_throw:
			detail += "\nThrow: %d%%" % roundi(grabber.throw_charge * 100.0)
		if OS.is_debug_build() and body is ImpactBody and body.impact_material != null:
			detail += "\n%s | %s\nLast impact: %.1f | thresholds: %.0f / %.0f" % [
				ImpactMaterial.Kind.keys()[body.impact_material.kind], ImpactBody.State.keys()[body.damage_state],
				body.last_impact_severity, body.impact_material.damage_threshold, body.impact_material.break_threshold]
			detail += "\nClosing: %.2f m/s | effective mass: %.2f kg\n%s" % [
				body.last_closing_speed, body.last_effective_mass, body.last_impact_source]
	_stats.text = "FPS: %d\n%s\nStance: %s" % [
		Engine.get_frames_per_second(), detail, SandboxPlayer.Stance.keys()[grabber.player.stance]]
