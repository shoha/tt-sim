extends CanvasLayer
class_name PauseOverlay

## Pause menu overlay with resume, settings, and return to title options.

signal resume_requested
signal main_menu_requested

@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton

var _tween: Tween


func _ready() -> void:
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	# Animate in
	_set_alpha(0.0)
	_animate_in()


func _set_alpha(alpha: float) -> void:
	$ColorRect.modulate.a = alpha
	$CenterContainer.modulate.a = alpha


func _animate_in() -> void:
	if _tween:
		_tween.kill()
	
	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.9, 0.9)
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property($ColorRect, "modulate:a", 1.0, 0.2)
	_tween.tween_property($CenterContainer, "modulate:a", 1.0, 0.2)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.2)
	
	await _tween.finished
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
