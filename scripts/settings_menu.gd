extends VBoxContainer

signal back_requested

var first_control: Control
var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _fullscreen: CheckButton
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	add_child(title)
	add_child(HSeparator.new())
	first_control = _slider("Mouse sensitivity", &"mouse_sensitivity", 0.0005, 0.01, 0.0001)
	_slider("Camera FOV (vertical)", &"camera_fov", 60, 110, 1)
	_slider("Master volume", &"master_volume", 0, 1, 0.01)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "Fullscreen"
	_fullscreen.custom_minimum_size.y = 48
	_fullscreen.toggled.connect(func(enabled: bool) -> void:
		GameSettings.update_setting(&"fullscreen", enabled)
		_update_status())
	add_child(_fullscreen)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.y = 48
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)
	refresh()


func _slider(title: String, key: StringName, minimum: float, maximum: float, step_size: float) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 18)
	row.add_child(value)
	_values[key] = value
	add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.custom_minimum_size.y = 32
	slider.value_changed.connect(func(next: float) -> void:
		GameSettings.update_setting(key, next)
		_update_value(key, next)
		_update_status())
	add_child(slider)
	_sliders[key] = slider
	return slider


func refresh() -> void:
	for key: StringName in _sliders:
		var value: float = GameSettings.get(key)
		_sliders[key].set_value_no_signal(value)
		_update_value(key, value)
	_fullscreen.set_pressed_no_signal(GameSettings.fullscreen)
	_update_status()


func _update_value(key: StringName, value: float) -> void:
	match key:
		&"mouse_sensitivity": _values[key].text = "%.2f×" % (value / GameSettings.DEFAULT_SENSITIVITY)
		&"camera_fov": _values[key].text = "%d°" % roundi(value)
		&"master_volume": _values[key].text = "%d%%" % roundi(value * 100)


func _update_status() -> void:
	_status.text = "Changes apply immediately and save automatically.\nEsc to go back."
	if GameSettings.save_error != OK:
		_status.text = "Changes applied, but could not save: %s" % error_string(GameSettings.save_error)
