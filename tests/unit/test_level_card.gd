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


func test_the_initial_is_the_first_letter_or_digit() -> void:
	assert_eq(LevelCard.initial_of("mossy Hollow"), "M")
	assert_eq(LevelCard.initial_of("_nettest_parity"), "N")
	assert_eq(LevelCard.initial_of("  3 Rivers"), "3")
	assert_eq(LevelCard.initial_of("___"), "")


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
	assert_null(card._thumb.texture, "no picture: the well's paper-inset wash shows")
	var well := card._thumb.get_parent() as Panel
	assert_eq(well.theme_type_variation, &"CardThumb")
	assert_true(card._placeholder.visible, "a painted placeholder, not a flat slab")


func test_placeholder_paints_the_map_and_a_real_thumbnail_hides_it() -> void:
	var card := LevelCard.new()
	add_child_autofree(card)
	card.setup(
		{
			"name": "sandy clearing",
			"folder": "sandy_clearing",
			"thumbnail": "",
			"path": "user://x/a/",
			"environment_preset": "outdoor_night",
		}
	)
	assert_true(card._placeholder.visible)
	var paint := card._placeholder.material as ShaderMaterial
	assert_eq(paint.get_shader_parameter(&"palette"), MapPlaceholder.NIGHT, "the mood's palette")
	assert_eq(paint.get_shader_parameter(&"seed"), MapPlaceholder.seed_of("sandy_clearing"))
	# A real thumbnail: write a tiny PNG to user:// and point the card at it.
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var path := "user://test_level_card_thumb.png"
	image.save_png(path)
	card.setup({"name": "Beta", "thumbnail": path, "path": "user://x/b/"})
	assert_false(card._placeholder.visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Every map paints its own, the same every time: the key picks a day palette and the shapes,
## a mood with a palette of its own wins.
func test_the_placeholder_is_stable_per_map_and_varies_across_maps() -> void:
	assert_eq(MapPlaceholder.seed_of("old_mill"), MapPlaceholder.seed_of("old_mill"))
	assert_ne(MapPlaceholder.seed_of("old_mill"), MapPlaceholder.seed_of("fen_crossing"))
	var palettes := {}
	for key in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]:
		var palette := MapPlaceholder.palette_of(key, "")
		assert_between(palette, 0, MapPlaceholder.DAY_PALETTES - 1, "no mood: a day palette")
		palettes[palette] = true
	assert_gt(palettes.size(), 1, "maps without a mood do not all paint alike")
	assert_eq(MapPlaceholder.palette_of("a", "arctic"), MapPlaceholder.SNOW)
	assert_eq(MapPlaceholder.palette_of("a", "outdoor_sunset"), MapPlaceholder.DUSK)


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
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	card._rename.gui_input.emit(esc)
	assert_false(card._rename.visible)
	assert_true(card._name.visible)
	assert_signal_emit_count(card, "rename_committed", 1)


func test_card_is_as_tall_as_its_content_once_laid_out() -> void:
	var card := _card(_info())
	card.custom_minimum_size = Vector2(300, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(card.get_combined_minimum_size().y, 200.0)
	assert_true(card.size.y >= card.get_combined_minimum_size().y)


func test_hover_zooms_the_thumbnail_inside_its_slot_and_never_scales_the_card() -> void:
	var card := _card(_info())
	card.size = Vector2(300, 240)
	await wait_frames(2)
	card._on_hover(true)
	await wait_seconds(Constants.ANIM_HOVER_SOFT_IN * 0.5)
	# Midway through the sine glide the zoom is still in flight -- strictly
	# past 1.0 and meaningfully short of the 1.04 target. The upper bound is
	# tightened to 1.03 (not the literal 1.04) because an abrupt tween that
	# already finished lands at ~1.039999 here -- inside (1.0, 1.04) by pure
	# floating-point noise, which would let a non-eased regression slip by.
	assert_true(card._thumb.scale.x > 1.0 and card._thumb.scale.x < 1.03)
	await wait_seconds(Constants.ANIM_HOVER_SOFT_IN * 0.5 + 0.05)
	assert_almost_eq(card._thumb.scale.x, 1.04, 0.001)
	assert_eq(card.scale, Vector2.ONE)
	assert_false(card.offset_transform_enabled)
	assert_eq(
		card._thumb.get_parent().clip_children,
		CanvasItem.CLIP_CHILDREN_AND_DRAW,
		"the zoom stays inside the well's rounded shape"
	)
	assert_almost_eq(card._thumb.pivot_offset.x, card._thumb.size.x * 0.5, 0.5)
	card._on_hover(false)
	await wait_seconds(Constants.ANIM_HOVER_SOFT_OUT + 0.05)
	assert_almost_eq(card._thumb.scale.x, 1.0, 0.001)


func test_hover_is_inert_during_rename() -> void:
	var card := _card(_info())
	await wait_frames(2)
	card.begin_rename()
	card._on_hover(true)
	await wait_seconds(Constants.ANIM_HOVER_SOFT_IN + 0.05)
	assert_eq(card._thumb.scale, Vector2.ONE)


func _double_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = true
	return event


## A single click selects (Host Game / Play Solo read that selection), so the card must
## keep reacting to presses as state -- but not as motion. The thumbnail's zoom is a
## hover affordance; driving it from press/release too made every press kill the hover
## tween, and because the dip ran at ANIM_PRESS (0.06s) while the regrow ran at
## ANIM_HOVER_SOFT_IN (0.24s), a double-click interrupted the slow regrow twice and
## pumped the thumbnail. Hover zoom must now hold steady across clicks.
func test_pressing_does_not_disturb_the_hover_zoom() -> void:
	var card := _card(_info())
	card._on_hover(true)
	await wait_seconds(Constants.ANIM_HOVER_SOFT_IN + 0.1)
	var hovered_scale: Vector2 = card._thumb.scale

	card.button_down.emit()
	card.button_up.emit()
	await wait_frames(2)

	assert_almost_eq(card._thumb.scale.x, hovered_scale.x, 0.001)
	assert_almost_eq(card._thumb.scale.y, hovered_scale.y, 0.001)


func test_edit_is_the_first_overflow_action() -> void:
	var card := _card(_info())

	assert_eq(card._menu.get_item_index(LevelCard.ACTION_EDIT), 0)
	assert_eq(card._menu.get_item_text(0), "Set up tokens")


func test_edit_requests_the_edit_action() -> void:
	var card := _card(_info())
	watch_signals(card)

	card._on_menu_id_pressed(LevelCard.ACTION_EDIT)

	assert_signal_emitted_with_parameters(card, "action_requested", [card.level_info, &"edit"])
