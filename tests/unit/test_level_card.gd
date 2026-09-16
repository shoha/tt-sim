extends GutTest

## LevelCard: caption grammar and relative times, placeholder art without a
## thumbnail, selection and activation signals, and the overflow actions.

const NOW := 1_800_000_000


func _info(overrides: Dictionary = {}) -> Dictionary:
	var info := {
		"path": "user://levels/clearing/",
		"folder": "clearing",
		"is_folder_based": true,
		"name": "Sandy Clearing",
		"token_count": 2,
		"modified_at": NOW - 3 * 3600,
		"environment_preset": "outdoor_day",
		"thumbnail": "",
	}
	info.merge(overrides, true)
	return info


func _card(info: Dictionary) -> LevelCard:
	var card := LevelCard.new()
	add_child_autofree(card)
	card.setup(info)
	return card


func test_caption_grammar_and_relative_times() -> void:
	assert_eq(
		LevelCard.caption_for(_info({"token_count": 1, "modified_at": NOW - 5}), NOW),
		"1 token, edited just now"
	)
	assert_eq(
		LevelCard.caption_for(_info({"modified_at": NOW - 120}), NOW), "2 tokens, edited 2 min ago"
	)
	assert_eq(LevelCard.caption_for(_info(), NOW), "2 tokens, edited 3 h ago")
	assert_eq(
		LevelCard.caption_for(_info({"modified_at": NOW - 30 * 3600}), NOW),
		"2 tokens, edited yesterday"
	)
	assert_eq(
		LevelCard.caption_for(_info({"modified_at": NOW - 5 * 86400}), NOW),
		"2 tokens, edited 5 days ago"
	)
	var old := LevelCard.caption_for(_info({"modified_at": NOW - 40 * 86400}), NOW)
	assert_true(old.begins_with("2 tokens, edited "))
	assert_true(old.ends_with("2027") or old.ends_with("2026"), old)
	assert_eq(LevelCard.caption_for(_info({"token_count": 0, "modified_at": 0}), NOW), "No tokens")


func test_setup_fills_name_caption_and_placeholder() -> void:
	var card := _card(_info())
	assert_eq(card._name.text, "Sandy Clearing")
	assert_true(card._caption.text.begins_with("2 tokens"))
	assert_not_null(card._thumb.texture, "placeholder painted when no thumbnail")
	assert_same(card._thumb.texture, SwatchTextures.sky_preview("clear_day"))


func test_press_selects_and_double_press_activates() -> void:
	var card := _card(_info())
	watch_signals(card)
	card._on_pressed()
	assert_signal_emitted_with_parameters(card, "selected", [card.level_info])
	card._on_gui_input(_double_click())
	assert_signal_emitted_with_parameters(card, "activated", [card.level_info])


func test_overflow_actions_and_lock() -> void:
	var card := _card(_info())
	watch_signals(card)
	card._on_menu_id_pressed(LevelCard.ACTION_DUPLICATE)
	assert_signal_emitted_with_parameters(card, "action_requested", [card.level_info, &"duplicate"])
	card._on_menu_id_pressed(LevelCard.ACTION_DELETE)
	assert_signal_emitted_with_parameters(card, "action_requested", [card.level_info, &"delete"])
	assert_false(card._menu.is_item_disabled(card._menu.get_item_index(LevelCard.ACTION_DELETE)))
	card.locked = true
	assert_true(card._menu.is_item_disabled(card._menu.get_item_index(LevelCard.ACTION_DELETE)))


func test_inline_rename_commits_on_submit_and_cancels_on_escape() -> void:
	var card := _card(_info())
	watch_signals(card)
	card.begin_rename()
	assert_true(card._rename.visible)
	assert_eq(card._rename.text, "Sandy Clearing")
	card._on_rename_submitted("Dusty Hollow")
	assert_signal_emitted_with_parameters(
		card, "rename_committed", [card.level_info, "Dusty Hollow"]
	)
	assert_false(card._rename.visible)
	card.begin_rename()
	card._cancel_rename()
	assert_false(card._rename.visible)
	assert_signal_emit_count(card, "rename_committed", 1)


func test_card_is_as_tall_as_its_content_once_laid_out() -> void:
	var card := _card(_info())
	card.custom_minimum_size = Vector2(300, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(card.get_combined_minimum_size().y, 200.0)
	assert_true(card.size.y >= card.get_combined_minimum_size().y)


func _double_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	return event
