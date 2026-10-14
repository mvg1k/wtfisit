extends Node

# The room remains a normal pausable scene; only menu controls process when paused.
const ROOM := preload("res://scenes/gamers_room.tscn")
enum Screen { MAIN, PLAYING, PAUSE, SETTINGS }

var screen: Screen = Screen.MAIN
var room: Node3D
var player: SandboxPlayer
var _settings_return: Screen = Screen.MAIN
var _transitioning: bool = false
var _overlay: Control
var _background: ColorRect
var _panel: PanelContainer
var _pages: Dictionary = {}
var _first_focus: Dictionary = {}


func _ready() -> void:
	_build_ui()
	show_screen(Screen.MAIN)


func _input(event: InputEvent) -> void:
	# Consume Escape before the existing player's/grabber's unhandled input.
	if event.is_action_pressed("release_mouse"):
		if not event.is_echo():
			match screen:
				Screen.PLAYING: pause_game()
				Screen.PAUSE: resume_game()
				Screen.SETTINGS: close_settings()
		get_viewport().set_input_as_handled()
	elif screen != Screen.PLAYING and not _is_ui_event(event):
		# Leave native keyboard/mouse navigation to Controls, block gameplay actions.
		get_viewport().set_input_as_handled()


func _is_ui_event(event: InputEvent) -> bool:
	if event is InputEventMouse or event is InputEventScreenTouch:
		return true
	for action: StringName in [&"ui_accept", &"ui_select", &"ui_focus_next", &"ui_focus_prev",
			&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"ui_home", &"ui_end"]:
		if event.is_action(action):
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == Screen.PLAYING:
		pause_game()


func play_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	_start_room.call_deferred()


func _start_room() -> void:
	_clear_room()
	get_tree().paused = false
	room = ROOM.instantiate()
	$Gameplay.add_child(room)
	player = room.get_node("Player") as SandboxPlayer
	var controls := room.get_node("DebugOverlay/Controls") as Label
	controls.text = controls.text.replace("Esc cursor", "Esc pause")
	show_screen(Screen.PLAYING)
	_transitioning = false


func _clear_room() -> void:
	if is_instance_valid(room):
		player.set_mouse_captured(false)
		player.get_node("Grabber").cancel_pending_input()
		$Gameplay.remove_child(room)
		room.queue_free()
	room = null
	player = null


func pause_game() -> void:
	if screen != Screen.PLAYING or not is_instance_valid(player) or _transitioning:
		return
	player.set_mouse_captured(false)
	player.get_node("Grabber").cancel_pending_input()
	get_tree().paused = true
	show_screen(Screen.PAUSE)


func resume_game() -> void:
	if screen != Screen.PAUSE or _transitioning:
		return
	show_screen(Screen.PLAYING)
	player.set_mouse_captured(true)
	get_tree().paused = false


func return_to_main() -> void:
	if _transitioning:
		return
	_transitioning = true
	_return_to_main.call_deferred()


func _return_to_main() -> void:
	_clear_room()
	get_tree().paused = false
	show_screen(Screen.MAIN)
	_transitioning = false


func open_settings() -> void:
	_settings_return = screen
	_pages[Screen.SETTINGS].refresh()
	show_screen(Screen.SETTINGS)


func close_settings() -> void:
	show_screen(_settings_return)


func show_screen(next: Screen) -> void:
	screen = next
	_overlay.visible = screen != Screen.PLAYING
	_background.color = Color(0.035, 0.043, 0.059, 1.0 if screen == Screen.MAIN or room == null else 0.88)
	for page: Screen in _pages:
		_pages[page].visible = page == screen
	if screen != Screen.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_first_focus[screen].grab_focus.call_deferred()
	else:
		get_viewport().gui_release_focus()


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.theme = _make_theme()
	$MenuLayer.add_child(_overlay)
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 24
	scroll.offset_right = -24
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_overlay.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	_panel.add_child(margin)
	var pages := VBoxContainer.new()
	margin.add_child(pages)
	var main := _page(pages, Screen.MAIN, "WHERE THE FUCK IS IT?", "A little chaos. A lot of searching.")
	_first_focus[Screen.MAIN] = _button(main, "Play", play_game)
	_button(main, "Settings", open_settings)
	_button(main, "Quit", func() -> void: get_tree().quit())
	_hint(main, "Arrow keys / Tab to navigate · Enter to select")
	var pause := _page(pages, Screen.PAUSE, "PAUSED", "The Gamer's Room")
	_first_focus[Screen.PAUSE] = _button(pause, "Resume", resume_game)
	_button(pause, "Restart", play_game)
	_button(pause, "Settings", open_settings)
	_button(pause, "Main Menu", return_to_main)
	_hint(pause, "Esc to resume")
	var settings := preload("res://scripts/settings_menu.gd").new()
	pages.add_child(settings)
	settings.back_requested.connect(close_settings)
	_pages[Screen.SETTINGS] = settings
	_first_focus[Screen.SETTINGS] = settings.first_control
	_overlay.resized.connect(_resize_panel)
	_resize_panel()


func _resize_panel() -> void:
	_panel.custom_minimum_size.x = clampf(_overlay.size.x - 48.0, 260.0, 560.0)


func _page(parent: Node, key: Screen, title: String, subtitle: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	parent.add_child(page)
	_pages[key] = page
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	page.add_child(label)
	_hint(page, subtitle)
	page.add_child(HSeparator.new())
	return page


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _hint(parent: Node, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("9daabd"))
	parent.add_child(label)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", Color("eef2f8"))
	theme.set_color("font_color", "Button", Color("eef2f8"))
	theme.set_stylebox("panel", "PanelContainer", _box(Color("131b28"), Color("29374c")))
	theme.set_stylebox("normal", "Button", _box(Color("202d40"), Color("34465f")))
	theme.set_stylebox("hover", "Button", _box(Color("304461"), Color("76b5cd")))
	theme.set_stylebox("pressed", "Button", _box(Color("3a536d"), Color("93d2e7")))
	var focus := _box(Color(0, 0, 0, 0), Color("93d2e7"))
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_stylebox("focus", "HSlider", focus)
	return theme


func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style
