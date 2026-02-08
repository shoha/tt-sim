extends AnimatedCanvasLayerPanel
class_name PauseOverlay

## Pause menu overlay with resume, settings, and return to title options.

signal resume_requested
signal main_menu_requested

@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton


func _on_panel_ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


func _on_after_animate_in() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()
	# Root will handle the actual unpause via pop_state


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
		"Danger"
	)
