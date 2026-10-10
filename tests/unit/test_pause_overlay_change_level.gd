extends GutTest

## The pause menu has no Change map (the table moves from the room drawer, TableMover),
## offers the host Return everyone to the room as a table move that asks nothing here, and
## its buttons are built on the shared menu design language.

const SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")


## Pause > Change map and its level picker are gone: the room drawer's Move the table here
## replaces them.
func test_there_is_no_change_map() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_false(overlay.has_signal("change_level_requested"))
	for button in overlay.find_children("*", "Button", true, false):
		assert_ne((button as Button).text, "Change map")


func test_header_reads_as_a_sentence() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.header.title_label.text, "Paused")
	assert_eq(overlay.header.caption_label.text, "Esc to resume")
	assert_true(overlay.header.caption_label.visible)


## Player-facing copy says "map", never "level" (W5), in sentence case, and leaving names
## its consequence for the role (W2); lost token moves are named only when there are some.
func test_rows_say_map_in_sentence_case_and_leaving_names_its_cost() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.edit_level_button.text, "Set up tokens")
	assert_eq(overlay.main_menu_button.text, "Return to title")
	assert_eq(overlay.quit_game_button.text, "Quit game")
	var host := PauseOverlay.leave_consequence(true, true, true)
	assert_string_contains(host, "ends for every player")
	assert_string_contains(host, PauseOverlay.TOKENS_LOST)
	assert_false(PauseOverlay.leave_consequence(true, true, false).contains("lost"))
	assert_eq(
		PauseOverlay.leave_consequence(true, false, true),
		"You leave the session; the others play on."
	)
	assert_eq(PauseOverlay.leave_consequence(false, false, true), PauseOverlay.TOKENS_LOST)
	assert_eq(
		PauseOverlay.leave_consequence(false, false, false), "Your tokens are saved to the map."
	)


func _open_dialogs() -> Array[ConfirmationDialogUI]:
	var found: Array[ConfirmationDialogUI] = []
	for child in get_tree().root.get_children():
		if child is ConfirmationDialogUI and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _close_dialogs() -> void:
	for dialog in _open_dialogs():
		dialog.queue_free()


## Return to title asks the same way it is named, and with unsaved moves it is a danger
## confirm that offers Save first, which saves before it leaves.
func test_return_to_title_with_unsaved_moves_offers_save() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	var saved: Array[bool] = []
	overlay.tokens_unsaved = func() -> bool: return true
	overlay.save_map = func() -> bool:
		saved.append(true)
		return true
	watch_signals(overlay)
	overlay._on_main_menu_pressed()
	var dialog: ConfirmationDialogUI = _open_dialogs().back()
	assert_eq(dialog.title_label.text, "Return to title?")
	assert_eq(dialog.confirm_button.text, "Return to title")
	assert_eq(dialog.confirm_button.theme_type_variation, &"Danger")
	assert_eq(dialog.cancel_button.text, "Cancel")
	assert_eq(dialog.message_label.text, PauseOverlay.TOKENS_LOST)
	var save_button := dialog.find_child("AlternateButton", true, false) as Button
	assert_not_null(save_button)
	assert_eq(save_button.text, PauseOverlay.SAVE_FIRST)
	save_button.pressed.emit()
	assert_eq(saved, [true] as Array[bool])
	assert_signal_emitted(overlay, "main_menu_requested")
	_close_dialogs()


## With nothing unsaved solo, nothing is lost: no danger, no lost-moves line, no save offer.
func test_return_to_title_with_everything_saved_is_not_a_danger() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.tokens_unsaved = func() -> bool: return false
	overlay.save_map = func() -> bool: return true
	overlay._on_main_menu_pressed()
	var dialog: ConfirmationDialogUI = _open_dialogs().back()
	assert_eq(dialog.confirm_button.theme_type_variation, &"Primary")
	assert_false(dialog.message_label.text.contains("lost"))
	assert_null(dialog.find_child("AlternateButton", true, false))
	_close_dialogs()


## Return everyone to the room is a table move: nothing is lost (the session keeps the
## changes), so the menu asks nothing and hands it to Root, whose TableMover asks only when
## the table changed.
func test_return_to_room_asks_nothing_here() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.tokens_unsaved = func() -> bool: return true
	var before := _open_dialogs().size()
	watch_signals(overlay)
	overlay._on_room_pressed()
	assert_signal_emitted(overlay, "room_requested")
	assert_eq(_open_dialogs().size(), before, "no confirm")


func test_resume_is_the_only_accent_action_and_nothing_shouts() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.resume_button.theme_type_variation, &"Primary")
	for button in [
		overlay.edit_level_button,
		overlay.settings_button,
		overlay.room_button,
		overlay.main_menu_button,
		overlay.quit_game_button,
	]:
		assert_eq(button.theme_type_variation, &"Secondary", button.text)


func test_every_row_carries_an_icon() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	for button in [
		overlay.resume_button,
		overlay.edit_level_button,
		overlay.settings_button,
		overlay.room_button,
		overlay.main_menu_button,
		overlay.quit_game_button,
	]:
		assert_not_null(button.icon, button.text)


func test_only_the_host_can_return_everyone_to_the_room() -> void:
	var offline = SCENE.instantiate()
	add_child_autofree(offline)
	assert_false(offline.room_button.visible, "solo play has no room")
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	var hosting = SCENE.instantiate()
	add_child_autofree(hosting)
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	assert_true(hosting.room_button.visible)
	assert_true(hosting.room_button.get_meta("ui_silent", false), "a quiet item")
