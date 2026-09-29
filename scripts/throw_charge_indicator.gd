class_name ThrowChargeIndicator
extends Control

@export var grabber: PhysicsGrabber
@export var radius: float = 18.0
@export var line_width: float = 2.0
@export var charge_color := Color(0.9, 0.95, 1.0, 0.9)

var displayed_charge: float = 0.0
var _full_seconds: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	# Read gameplay state directly; no separate charge timer or release state.
	visible = is_instance_valid(grabber) and is_instance_valid(grabber.held_body) \
		and grabber.is_charging_throw and grabber.player.mouse_captured
	if not visible:
		displayed_charge = 0.0
		_full_seconds = 0.0
		return
	displayed_charge = grabber.throw_charge
	_full_seconds = _full_seconds + delta if displayed_charge >= 1.0 else 0.0
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.05, 0.06, 0.08, 0.65), line_width + 2.0, true)
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.18), line_width, true)
	if displayed_charge > 0.0:
		var color := charge_color
		if displayed_charge >= 1.0:
			color.a *= 0.85 + 0.15 * cos(_full_seconds * TAU * 1.5)
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * displayed_charge,
			64, color, line_width, true)
