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
		{
			"path": "user://x/b/",
			"folder": "b",
			"is_folder_based": true,
			"name": "Bravo",
			"token_count": 0,
			"modified_at": 20,
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


func test_refresh_notifies_choose_button_when_the_list_changes() -> void:
	var dialog := _dialog()
	dialog.grid.select(_levels()[0]["path"])
	dialog.grid.refresh()
	assert_false(dialog.choose_button.disabled)
	dialog.grid.provider = func() -> Array: return []
	dialog.grid.refresh()
	assert_true(dialog.choose_button.disabled)


func test_cancel_after_choose_is_ignored() -> void:
	var dialog := _dialog()
	watch_signals(dialog)
	dialog.grid._cards[0]._on_pressed()
	dialog._on_choose_pressed()
	dialog._on_cancel_pressed()
	assert_signal_emit_count(dialog, "level_chosen", 1)
	assert_true(get_signal_emit_count(dialog, "closed") <= 1)
