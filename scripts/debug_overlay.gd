extends CanvasLayer

@export var grabber: PhysicsGrabber
@export var debug_visible: bool = true
@onready var _stats: Label = %Stats
var _elapsed: float = 0.0


func _ready() -> void:
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
	_stats.text = "FPS: %d\n%s\nStance: %s" % [
		Engine.get_frames_per_second(), detail, SandboxPlayer.Stance.keys()[grabber.player.stance]]
