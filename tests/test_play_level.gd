extends Node3D

## Quick-play test scene for rapid iteration on game feel.
## Run this scene directly (F6 in editor) to skip menus and jump straight
## into a saved level with full camera, drag-and-drop, and token interaction.
##
## Features:
##   - Lists all saved levels from user://levels/
##   - Auto-plays the most recently modified level (toggle via AUTO_PLAY)
##   - Press R to reload the current level instantly
##   - Press Escape to return to the level selector
##   - Press L to toggle the level selector while playing

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const LOADING_OVERLAY_SCENE := preload("res://scenes/ui/loading_overlay.tscn")

## If true, automatically loads the most recently modified level on startup
@export var auto_play: bool = true

var _level_play_controller: LevelPlayController = null
var _game_map: GameMap = null
var _loading_overlay = null
var _saved_levels: Array[Dictionary] = []
var _active_level_data: LevelData = null

# UI references
var _selector_canvas: CanvasLayer = null
var _selector_panel: PanelContainer = null
var _level_dropdown: OptionButton = null
var _play_button: Button = null
var _hud_panel: PanelContainer = null
var _level_name_label: Label = null


func _ready() -> void:
	_setup_level_play_controller()
	_setup_loading_overlay()
	_build_selector_ui()
	_build_hud_ui()
	_refresh_level_list()

	if auto_play and _saved_levels.size() > 0:
		# Auto-play the most recently modified level
		_play_level_at_index(0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_R:
			# Reload current level
			if _active_level_data:
				print("TestPlayLevel: Reloading level...")
				_play_current_level()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			# Return to level selector
			if _game_map:
				_stop_playing()
				get_viewport().set_input_as_handled()
		KEY_L:
			# Toggle level selector overlay while playing
			if _selector_canvas:
				_selector_canvas.visible = not _selector_canvas.visible
				get_viewport().set_input_as_handled()


# ============================================================================
# Level Play Controller
# ============================================================================


func _setup_level_play_controller() -> void:
	_level_play_controller = LevelPlayController.new()
	add_child(_level_play_controller)
	_level_play_controller.level_loaded.connect(_on_level_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)
	_level_play_controller.level_loading_started.connect(_on_level_loading_started)
	_level_play_controller.level_loading_progress.connect(_on_level_loading_progress)
	_level_play_controller.level_loading_completed.connect(_on_level_loading_completed)


func _setup_loading_overlay() -> void:
	_loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(_loading_overlay)


# ============================================================================
# Level Selection & Playback
# ============================================================================


func _refresh_level_list() -> void:
	_saved_levels = LevelManager.get_saved_levels()
	_level_dropdown.clear()

	if _saved_levels.size() == 0:
		_level_dropdown.add_item("(no saved levels found)")
		_play_button.disabled = true
		return

	_play_button.disabled = false
	for i in range(_saved_levels.size()):
		var info = _saved_levels[i]
		var label_text = info.name
		if info.token_count > 0:
			label_text += " (%d tokens)" % info.token_count
		_level_dropdown.add_item(label_text, i)


func _play_level_at_index(index: int) -> void:
	if index < 0 or index >= _saved_levels.size():
		return

	var info = _saved_levels[index]
	var level_data: LevelData = null

	if info.is_folder_based:
		level_data = LevelManager.load_level_folder(info.folder, false)
	else:
		level_data = LevelManager.load_level(info.path, false)

	if not level_data:
		push_error("TestPlayLevel: Failed to load level: " + info.name)
		return

	_active_level_data = level_data
	_start_playing(level_data)


func _play_current_level() -> void:
	if not _active_level_data:
		return

	# Reload from disk to get latest changes
	var info = _saved_levels[_level_dropdown.selected]
	var level_data: LevelData = null

	if info.is_folder_based:
		level_data = LevelManager.load_level_folder(info.folder, false)
	else:
		level_data = LevelManager.load_level(info.path, false)

	if level_data:
		_active_level_data = level_data

	# If already playing, reload in-place
	if _game_map and _level_play_controller:
		_level_play_controller.play_level(_active_level_data)
	else:
		_start_playing(_active_level_data)


func _start_playing(level_data: LevelData) -> void:
	# Hide selector, show HUD
	_selector_canvas.visible = false
	_hud_panel.visible = true
	_level_name_label.text = level_data.level_name

	# Create GameMap if needed
	if not _game_map:
		_game_map = GAME_MAP_SCENE.instantiate()
		add_child(_game_map)
		_level_play_controller.setup(_game_map)
		_game_map.setup(_level_play_controller)

	_level_play_controller.play_level(level_data)


func _stop_playing() -> void:
	# Clean up the level
	if _level_play_controller:
		_level_play_controller.reset_loading_state()
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	if _game_map:
		_game_map.queue_free()
		_game_map = null

	# Show selector, hide HUD
	_selector_canvas.visible = true
	_hud_panel.visible = false
	_refresh_level_list()


# ============================================================================
# Signal Handlers
# ============================================================================


func _on_level_loaded(_level_data: LevelData) -> void:
	print("TestPlayLevel: Level loaded - %s" % _level_data.level_name)


func _on_level_cleared() -> void:
	pass


func _on_level_loading_started() -> void:
	if _loading_overlay:
		_loading_overlay.show_loading("Loading Level...")


func _on_level_loading_progress(progress: float, status: String) -> void:
	if _loading_overlay:
		_loading_overlay.set_progress(progress, status)


func _on_level_loading_completed() -> void:
	if _loading_overlay:
		_loading_overlay.hide_loading()


# ============================================================================
# UI Construction
# ============================================================================


func _build_selector_ui() -> void:
	_selector_canvas = CanvasLayer.new()
	_selector_canvas.layer = 10
	add_child(_selector_canvas)

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selector_canvas.add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selector_canvas.add_child(center)

	# Panel
	_selector_panel = PanelContainer.new()
	_selector_panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(_selector_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_selector_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Quick Play - Test Scene"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = (
		"Select a saved level to play instantly." + "\nPress R to reload, Escape to return here."
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(subtitle)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Level dropdown
	var dropdown_label = Label.new()
	dropdown_label.text = "Level:"
	vbox.add_child(dropdown_label)

	_level_dropdown = OptionButton.new()
	_level_dropdown.custom_minimum_size.y = 36
	vbox.add_child(_level_dropdown)

	# Auto-play checkbox
	var auto_play_check = CheckBox.new()
	auto_play_check.text = "Auto-play most recent level on startup"
	auto_play_check.button_pressed = auto_play
	auto_play_check.toggled.connect(func(pressed): auto_play = pressed)
	vbox.add_child(auto_play_check)

	# Play button
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.custom_minimum_size.y = 40
	_play_button.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_button)


func _build_hud_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	_hud_panel = PanelContainer.new()
	_hud_panel.visible = false
	_hud_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud_panel.position = Vector2(8, 8)
	canvas.add_child(_hud_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_hud_panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	_level_name_label = Label.new()
	_level_name_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_level_name_label)

	var sep = VSeparator.new()
	hbox.add_child(sep)

	var reload_btn = Button.new()
	reload_btn.text = "Reload (R)"
	reload_btn.pressed.connect(_play_current_level)
	hbox.add_child(reload_btn)

	var back_btn = Button.new()
	back_btn.text = "Back (Esc)"
	back_btn.pressed.connect(_stop_playing)
	hbox.add_child(back_btn)


func _on_play_pressed() -> void:
	var index = _level_dropdown.selected
	if index >= 0:
		_play_level_at_index(index)
