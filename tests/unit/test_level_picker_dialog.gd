extends GutTest

## LevelPickerDialog: Choose stays disabled until a card is selected, choosing
## emits the info, double-click chooses too, Cancel just closes.

const SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")


func _levels() -> Array[Dictionary]:
	return [
		{
			"path": "user://x/a/",
			"folder": "a",
			"is_folder_based": true,
			"name": "Alpha",
			"token_count": 0,
			"modified_at": 10,
			"environment_preset": "",
			"thumbnail": ""
		},
	]


func _dialog() -> LevelPickerDialog:
	var dialog: LevelPickerDialog = SCENE.instantiate()
	dialog.provider = _levels
	dialog.setup("Pick one")
	add_child_autofree(dialog)
	return dialog


func test_choose_enables_with_selection_and_emits() -> void:
	var dialog := _dialog()
	assert_eq(dialog.title_label.text, "Pick one")
	assert_true(dialog.choose_button.disabled)
	watch_signals(dialog)
	dialog.grid._cards[0]._on_pressed()
	assert_false(dialog.choose_button.disabled)
	dialog._on_choose_pressed()
	assert_signal_emitted_with_parameters(dialog, "level_chosen", [_levels()[0]])


func test_activation_chooses_directly() -> void:
	var dialog := _dialog()
	watch_signals(dialog)
	dialog.grid.level_activated.emit(_levels()[0])
	assert_signal_emitted(dialog, "level_chosen")


func test_cancel_only_closes() -> void:
	var dialog := _dialog()
	watch_signals(dialog)
	dialog._on_cancel_pressed()
	assert_signal_not_emitted(dialog, "level_chosen")
