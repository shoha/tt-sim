class_name PauseOverlay
extends AnimatedCanvasLayerPanel

## Pause menu overlay with resume, settings, and return to title options.

signal resume_requested
signal main_menu_requested
signal change_level_requested(level_info: Dictionary)

const LEVEL_PICKER_SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")

var header: MenuHeader
var resume_button: Button
var edit_level_button: Button
var change_level_button: Button
var settings_button: Button
var main_menu_button: Button
var quit_game_button: Button


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	header.setup("Paused", "Esc to resume")

	resume_button = UiActions.primary("Resume", "player-play", "", box)
	resume_button.pressed.connect(_on_resume_pressed)
	edit_level_button = UiActions.secondary("Edit Level", "wand", box)
	edit_level_button.pressed.connect(_on_edit_level_pressed)
	change_level_button = UiActions.secondary("Change Level", "map", box)
	change_level_button.pressed.connect(_on_change_level_pressed)
	settings_button = UiActions.secondary("Settings", "settings", box)
	settings_button.pressed.connect(_on_settings_pressed)
	box.add_child(HSeparator.new())
	# Leaving is quiet here; the confirmation that follows carries the red.
	main_menu_button = UiActions.secondary("Return to Title", "home", box)
	main_menu_button.set_meta("ui_silent", true)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_game_button = UiActions.secondary("Quit Game", "logout", box)
	quit_game_button.set_meta("ui_silent", true)
	quit_game_button.pressed.connect(_on_quit_game_pressed)

	_setup_blur_backdrop()

	# Only show "Edit Level" and "Change Level" for the GM / local player
	edit_level_button.visible = NetworkManager.has_gm_access()
	change_level_button.visible = NetworkManager.has_gm_access()


## Replace the flat dark backdrop with a blurred-background shader
func _setup_blur_backdrop() -> void:
	var shader = Shader.new()
	shader.code = (
		"shader_type canvas_item;\n"
		+ "\n"
		+ "uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;\n"
		+ "uniform float blur_amount : hint_range(0, 10) = 2.5;\n"
		+ "\n"
		+ "void fragment() {\n"
		+ "    vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;\n"
		+ "    vec4 col = vec4(0.0);\n"
		+ "    float total = 0.0;\n"
		+ "    for (int x = -3; x <= 3; x++) {\n"
		+ "        for (int y = -3; y <= 3; y++) {\n"
		+ "            float w = 1.0 / (1.0 + float(x*x + y*y));\n"
		+ "            col += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * ps) * w;\n"
		+ "            total += w;\n"
		+ "        }\n"
		+ "    }\n"
		+ "    col /= total;\n"
		+ "    // Darken the blurred result to keep text readable\n"
		+ "    COLOR = vec4(col.rgb * 0.4, 1.0);\n"
		+ "}\n"
	)
	var mat = ShaderMaterial.new()
	mat.shader = shader
	$ColorRect.material = mat


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children($CenterContainer/PanelContainer/VBoxContainer)


func _on_after_animate_in() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()
	# Root will handle the actual unpause via pop_state


func _on_edit_level_pressed() -> void:
	# Resume first, then open the editor via EventBus. Empty path: edit the level
	# that is currently playing, which is the only one reachable from the pause menu.
	resume_requested.emit()
	EventBus.open_editor_requested.emit("")


func _on_change_level_pressed() -> void:
	var picker: LevelPickerDialog = LEVEL_PICKER_SCENE.instantiate()
	picker.setup("Change level", LevelManager.current_level_path)
	picker.level_chosen.connect(_on_level_picked)
	get_tree().root.add_child(picker)
	# Returning to the title (or otherwise leaving the tree) while the picker
	# is still open must not strand it floating over the title screen.
	tree_exiting.connect(picker.queue_free)


func _on_level_picked(info: Dictionary) -> void:
	change_level_requested.emit(info)


func _on_settings_pressed() -> void:
	UIManager.open_settings()


func _on_main_menu_pressed() -> void:
	# Show confirmation before returning to title
	UIManager.show_confirmation(
		"Return to Title?",
		"Any unsaved progress will be lost.",
		"Return",
		"Cancel",
		func(): main_menu_requested.emit(),
		Callable(),
		"Danger",
		AudioManager.play_leave_game,
	)


func _on_quit_game_pressed() -> void:
	UIManager.show_confirmation(
		"Quit Game?",
		"Any unsaved progress will be lost.",
		"Quit",
		"Cancel",
		func(): get_tree().quit(),
		Callable(),
		"Danger",
	)
