extends GutTest

## The pause menu offers Change Level to the GM and relays the picked level, offers the
## host Return everyone to the room, and its buttons are built on the shared menu design
## language.

const SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")


func test_change_level_visibility_matches_edit_level() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.change_level_button.visible, overlay.edit_level_button.visible)


func test_picked_level_is_relayed() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	watch_signals(overlay)
	var info := {"path": "user://x/a/", "name": "Alpha"}
	overlay._on_level_picked(info)
	assert_signal_emitted_with_parameters(overlay, "change_level_requested", [info])


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
	assert_eq(overlay.change_level_button.text, "Change map")
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


## Return everyone to the room loses unsaved moves: then it is a danger confirm, Cancel safe.
func test_return_to_room_with_unsaved_moves_is_a_danger() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	overlay.tokens_unsaved = func() -> bool: return true
	overlay._on_room_pressed()
	var dialog: ConfirmationDialogUI = _open_dialogs().back()
	assert_eq(dialog.title_label.text, "Return to the room?")
	assert_eq(dialog.confirm_button.text, "Return to the room")
	assert_eq(dialog.confirm_button.theme_type_variation, &"Danger")
	assert_eq(dialog.cancel_button.text, "Cancel")
	assert_string_contains(dialog.message_label.text, PauseOverlay.TOKENS_LOST)
	_close_dialogs()


func test_resume_is_the_only_accent_action_and_nothing_shouts() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.resume_button.theme_type_variation, &"Primary")
	for button in [
		overlay.edit_level_button,
		overlay.change_level_button,
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
		overlay.change_level_button,
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
