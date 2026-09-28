extends CanvasLayer

@export var run: SearchRun
@onready var _objective: Label = %Objective
@onready var _result: Label = %Result
@onready var _result_background: ColorRect = %ResultBackground
@onready var _debug: Label = %SearchDebug
var _elapsed: float = 0.0


func _ready() -> void:
	run.state_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.05:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	_result.visible = run.state in [SearchRun.State.COMPLETED, SearchRun.State.UNAVAILABLE]
	_result_background.visible = _result.visible
	match run.state:
		SearchRun.State.PREPARING:
			_objective.text = "GET READY"
		SearchRun.State.SEARCHING:
			_objective.text = "FIND YOUR %s\n%s" % [run.target_name, format_time(run.elapsed_seconds)]
		SearchRun.State.COMPLETED:
			_objective.text = ""
			_result.text = "FOUND YOUR %s\n\nTIME: %s\n\n[ENTER] SEARCH AGAIN" % [
				run.target_name, format_time(run.elapsed_seconds)]
		SearchRun.State.UNAVAILABLE:
			_objective.text = ""
			_result.text = "SEARCH UNAVAILABLE\n%s\n\n[ENTER] RETRY" % run.error_message
	_debug.visible = OS.is_debug_build() and run.debug_search_visible
	if _debug.visible:
		var spot_name := String(run.current_spot.name) if is_instance_valid(run.current_spot) else "-"
		var category: String = SearchSpot.Category.keys()[run.current_spot.search_category] if is_instance_valid(run.current_spot) else "-"
		_debug.text = "SEARCH DEBUG\nState: %s\nTarget: %s\nSpot: %s\nCategory: %s\nF4 hide | F7 new search" % [
			SearchRun.State.keys()[run.state], run.target_name, spot_name, category]


static func format_time(seconds: float) -> String:
	var centiseconds := int(maxf(seconds, 0.0) * 100.0)
	@warning_ignore("integer_division")
	var minutes: int = centiseconds / 6000
	@warning_ignore("integer_division")
	var whole_seconds: int = (centiseconds / 100) % 60
	return "%02d:%02d.%02d" % [minutes, whole_seconds, centiseconds % 100]
