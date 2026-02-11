extends AnimatedCanvasLayerPanel
class_name LevelBrowserDialog

## Dialog that lists saved levels for quick local play.
## Loads the selected level via LevelManager which triggers the
## root state machine's play transition.

signal closed

@onready var title_label: Label = %TitleLabel
@onready var level_list: VBoxContainer = %LevelList
@onready var empty_label: Label = %EmptyLabel
@onready var cancel_button: Button = %CancelButton


func _on_panel_ready() -> void:
	cancel_button.set_meta("ui_silent", true)
	cancel_button.pressed.connect(_on_cancel_pressed)
	_populate_levels()


func _on_after_animate_in() -> void:
	cancel_button.grab_focus()


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _populate_levels() -> void:
	var levels := LevelManager.get_saved_levels()

	if levels.is_empty():
		empty_label.visible = true
		return

	empty_label.visible = false

	for level_info in levels:
		var btn := Button.new()
		btn.text = level_info.get("name", "Untitled")
		var token_count: int = level_info.get("token_count", 0)
		if token_count > 0:
			btn.text += "  (%d tokens)" % token_count
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.theme_type_variation = &"Secondary"
		btn.pressed.connect(_on_level_selected.bind(level_info))
		level_list.add_child(btn)


func _on_level_selected(level_info: Dictionary) -> void:
	AudioManager.play_confirm()
	var path: String = level_info.get("path", "")
	if path.is_empty():
		return
	# Load level — LevelManager.level_loaded triggers root state transition
	LevelManager.load_level(path, true)
	animate_out()


func _on_cancel_pressed() -> void:
	AudioManager.play_cancel()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
