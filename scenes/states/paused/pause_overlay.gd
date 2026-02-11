extends AnimatedCanvasLayerPanel
class_name PauseOverlay

## Pause menu overlay with resume, settings, and return to title options.

signal resume_requested
signal main_menu_requested

@onready var resume_button: Button = %ResumeButton
@onready var edit_level_button: Button = %EditLevelButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton


func _on_panel_ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	edit_level_button.pressed.connect(_on_edit_level_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.set_meta("ui_silent", true)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_setup_blur_backdrop()

	# Only show "Edit Level" for the GM / local player
	edit_level_button.visible = NetworkManager.is_gm() or not NetworkManager.is_networked()


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


func _on_after_animate_in() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()
	# Root will handle the actual unpause via pop_state


func _on_edit_level_pressed() -> void:
	# Resume first, then open the editor via EventBus
	resume_requested.emit()
	EventBus.open_editor_requested.emit()


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
