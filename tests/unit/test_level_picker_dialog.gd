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


## A picker's cards only choose: no management menu (that is the library's, on the title).
func test_picker_cards_have_no_management_menu() -> void:
	var dialog := _dialog()
	assert_false(dialog.grid.manageable)
	for card in dialog.grid._cards:
		assert_false(card._menu_button.visible)
	var library := LevelGrid.new()
	library.provider = _levels
	add_child_autofree(library)
	library.refresh()
	assert_true(library._cards[0]._menu_button.visible, "the library's cards keep it")


## The grid grows with the canvas: a short library shows whole at 1080, and on the 1280x720
## canvas the sheet stays on screen and the grid scrolls.
func test_the_grid_grows_with_the_canvas_up_to_a_maximum() -> void:
	for canvas in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var count := 5 if canvas.y == 720 else 3
		var levels := func() -> Array[Dictionary]:
			var out: Array[Dictionary] = []
			for i in count:
				var info: Dictionary = _levels()[0].duplicate()
				info.path = "user://x/%d/" % i
				info.folder = str(i)
				out.append(info)
			return out
		var host := SubViewport.new()
		host.size = canvas
		host.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child_autofree(host)
		var dialog: LevelPickerDialog = SCENE.instantiate()
		dialog.provider = levels
		dialog.setup("Pick one")
		host.add_child(dialog)
		await wait_process_frames(6)
		var slot := dialog.grid_slot.size.y
		var content := dialog.grid.content_height()
		var sheet := (dialog.grid_slot.get_parent().get_parent() as Control).get_global_rect()
		if canvas.y == 1080:
			assert_almost_eq(slot, content, 1.0, "1080: every card shows whole")
		else:
			assert_lt(slot, content, "720: a longer library scrolls")
			assert_true(Rect2(Vector2.ZERO, Vector2(canvas)).encloses(sheet), "on the canvas")
		assert_lte(slot, LevelPickerDialog.MAX_GRID_HEIGHT)
		UIManager.unregister_overlay(dialog.get_node("ColorRect") as Control)


func test_cancel_after_choose_is_ignored() -> void:
	var dialog := _dialog()
	watch_signals(dialog)
	dialog.grid._cards[0]._on_pressed()
	dialog._on_choose_pressed()
	dialog._on_cancel_pressed()
	assert_signal_emit_count(dialog, "level_chosen", 1)
	assert_true(get_signal_emit_count(dialog, "closed") <= 1)
