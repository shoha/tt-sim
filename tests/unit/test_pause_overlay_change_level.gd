extends GutTest

## The pause menu offers Change Level to the GM and relays the picked level,
## and its buttons are built on the shared menu design language.

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


func test_resume_is_the_only_accent_action_and_nothing_shouts() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.resume_button.theme_type_variation, &"")
	for button in [
		overlay.edit_level_button,
		overlay.change_level_button,
		overlay.settings_button,
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
		overlay.main_menu_button,
		overlay.quit_game_button,
	]:
		assert_not_null(button.icon, button.text)
