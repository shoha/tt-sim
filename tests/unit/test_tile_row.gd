extends GutTest

## TileRow: single-select rows keep one tile pressed and report user clicks;
## multi-select rows toggle tiles independently. Programmatic select() and
## set_tile_on() never emit.


func _single() -> TileRow:
	var row := TileRow.new()
	add_child_autofree(row)
	row.add_tile(&"a", "A", "sun")
	row.add_tile(&"b", "B")
	return row


func _multi() -> TileRow:
	var row := TileRow.new()
	row.multi_select = true
	add_child_autofree(row)
	row.add_tile(&"rain", "Rain", "cloud-rain")
	row.add_tile(&"snow", "Snow", "snowflake")
	return row


func test_select_is_silent_and_presses_only_that_tile() -> void:
	var row := _single()
	watch_signals(row)
	row.select(&"b")
	assert_eq(row.selected, &"b")
	assert_true(row._tiles[&"b"].button_pressed)
	assert_false(row._tiles[&"a"].button_pressed)
	assert_signal_not_emitted(row, "selection_changed")


func test_user_click_emits_selection_changed_once() -> void:
	var row := _single()
	row.select(&"a")
	watch_signals(row)
	row._tiles[&"b"].button_pressed = true
	assert_signal_emitted_with_parameters(row, "selection_changed", [&"b"])
	assert_signal_emit_count(row, "selection_changed", 1)
	assert_eq(row.selected, &"b")


func test_multi_select_toggles_independently() -> void:
	var row := _multi()
	watch_signals(row)
	row._tiles[&"rain"].button_pressed = true
	row._tiles[&"snow"].button_pressed = true
	assert_true(row.is_on(&"rain"))
	assert_true(row.is_on(&"snow"))
	assert_signal_emit_count(row, "tile_toggled", 2)
	row._tiles[&"rain"].button_pressed = false
	assert_false(row.is_on(&"rain"))
	assert_signal_emitted_with_parameters(row, "tile_toggled", [&"rain", false], 2)


func test_set_tile_on_is_silent() -> void:
	var row := _multi()
	watch_signals(row)
	row.set_tile_on(&"snow", true)
	assert_true(row.is_on(&"snow"))
	assert_signal_not_emitted(row, "tile_toggled")


func test_visibility_and_lookup() -> void:
	var row := _single()
	row.set_tile_visible(&"b", false)
	assert_false(row._tiles[&"b"].visible)
	assert_true(row.has_tile(&"a"))
	assert_false(row.has_tile(&"zzz"))


func test_icon_is_optional() -> void:
	var row := _single()
	assert_not_null(row._tiles[&"a"].icon)
	assert_null(row._tiles[&"b"].icon)


func test_texture_icon_wins_over_icon_name() -> void:
	var row := TileRow.new()
	add_child_autofree(row)
	var texture := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var tile := row.add_tile(&"painted", "Painted", "sun", "", texture)
	assert_eq(tile.icon, texture)


func test_columns_size_tiles_evenly_and_wrap_at_the_count() -> void:
	var row := TileRow.new()
	row.columns = 3
	add_child_autofree(row)
	for id in ["a", "b", "c", "d", "e", "f"]:
		row.add_tile(StringName(id), id.to_upper())
	row.size = Vector2(300, 0)
	row._fit_columns()
	var expected_width := floorf((300.0 - 2.0 * 6.0) / 3.0)
	for id in row._tiles:
		assert_eq(row._tiles[id].custom_minimum_size.x, expected_width, String(id))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(row._tiles[&"a"].position.y, row._tiles[&"c"].position.y, "first line holds three")
	assert_gt(row._tiles[&"d"].position.y, row._tiles[&"a"].position.y, "fourth tile wraps")


func test_columns_zero_keeps_natural_tile_widths() -> void:
	var row := _single()
	row.size = Vector2(300, 0)
	row._fit_columns()
	assert_eq(row._tiles[&"a"].custom_minimum_size, row.tile_min_size)


func test_hover_signals_follow_the_pointer_and_never_select() -> void:
	var row := _single()
	watch_signals(row)
	row._on_tile_hover(&"a", true)
	assert_signal_emitted_with_parameters(row, "tile_hovered", [&"a"])
	row._on_tile_hover(&"a", false)
	assert_signal_emitted_with_parameters(row, "tile_unhovered", [&"a"])
	assert_signal_not_emitted(row, "selection_changed")
	row.select(&"b")
	assert_signal_emit_count(row, "tile_hovered", 1, "select never hovers")
