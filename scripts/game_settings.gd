extends Node

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.0025
const DEFAULT_FOV := 75.0

var mouse_sensitivity: float = DEFAULT_SENSITIVITY
var camera_fov: float = DEFAULT_FOV
var master_volume: float = 1.0
var fullscreen: bool = false
var save_error: Error = OK


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load settings: %s" % error_string(error))
	mouse_sensitivity = _bounded(config.get_value("controls", "mouse_sensitivity", DEFAULT_SENSITIVITY),
		DEFAULT_SENSITIVITY, 0.0005, 0.01)
	camera_fov = _bounded(config.get_value("camera", "fov", DEFAULT_FOV), DEFAULT_FOV, 60.0, 110.0)
	master_volume = _bounded(config.get_value("audio", "master_volume", 1.0), 1.0, 0.0, 1.0)
	var saved_fullscreen: Variant = config.get_value("display", "fullscreen", false)
	fullscreen = saved_fullscreen if saved_fullscreen is bool else false
	apply_settings()


func update_setting(key: StringName, value: Variant) -> void:
	match key:
		&"mouse_sensitivity":
			mouse_sensitivity = _bounded(value, DEFAULT_SENSITIVITY, 0.0005, 0.01)
		&"camera_fov":
			camera_fov = _bounded(value, DEFAULT_FOV, 60.0, 110.0)
		&"master_volume":
			master_volume = _bounded(value, 1.0, 0.0, 1.0)
		&"fullscreen":
			fullscreen = value == true
		_:
			return
	apply_settings()
	save_settings()


func apply_settings() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(master, master_volume <= 0.0)
	if DisplayServer.get_name() != "headless":
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)
	changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("camera", "fov", camera_fov)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("display", "fullscreen", fullscreen)
	save_error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_warning("Could not save settings: %s" % error_string(save_error))


func _bounded(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)
