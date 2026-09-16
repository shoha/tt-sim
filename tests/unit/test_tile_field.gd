extends GutTest

## TileField owns a caption above a full-width TileRow, tints the caption when
## overridden, and reports a right-click on the caption as a reset request.


func _field() -> TileField:
	var field := TileField.new()
	field.caption = "Sky"
	field.tiles.add_tile(&"a", "A")
	field.tiles.add_tile(&"b", "B")
	add_child_autofree(field)
	return field


func test_caption_and_tiles_are_laid_out_full_width() -> void:
	var field := _field()
	assert_eq(field._caption.text, "Sky")
	assert_eq(field.tiles.get_parent(), field)
	assert_eq(field.tiles.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_true(field.tiles.has_tile(&"a"))


func test_tiles_usable_before_entering_tree() -> void:
	var field := TileField.new()
	field.tiles.multi_select = true
	field.tiles.add_tile(&"x", "X")
	add_child_autofree(field)
	assert_true(field.tiles.multi_select)
	assert_true(field.tiles.has_tile(&"x"))


func test_overridden_tints_caption_and_right_click_resets() -> void:
	var field := _field()
	watch_signals(field)
	field.overridden = true
	assert_eq(field._caption.get_theme_color("font_color"), ThemeColors.ACCENT)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	field._on_caption_gui_input(click)
	assert_signal_emitted(field, "reset_requested")
	field.overridden = false
	assert_false(field._caption.has_theme_color_override("font_color"))
